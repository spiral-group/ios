//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import BackgroundTasks
import Combine
import Intents
import MatrixRustSDK
import SwiftUI
import Version

// AGENT-PLATFORM: our NSE tap-routing + approval reconcile hooks
// push the upstream class over the 1000-line cap (same escape hatch as
// ClientProxy.swift).
// swiftlint:disable:next type_body_length
class AppCoordinator: AppCoordinatorProtocol, AuthenticationFlowCoordinatorDelegate, NotificationManagerDelegate, SecureWindowManagerDelegate {
    private let stateMachine: AppCoordinatorStateMachine
    private let navigationRootCoordinator: NavigationRootCoordinator
    private let userSessionStore: UserSessionStoreProtocol
    // periphery:ignore - retaining purpose
    private let targetConfiguration: Target.ConfigurationResult
    private let appMediator: AppMediator
    private let appSettings: AppSettings
    private let analyticsService: AnalyticsServiceProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    
    private let appDelegate: AppDelegate
    private let appHooks: AppHooks
    private let bugReportService: BugReportServiceProtocol
    private var callKitService: CallKitServiceProtocol
    
    /// Common background task to continue long-running tasks in the background.
    private var backgroundTask: UIBackgroundTaskIdentifier?
    
    private var userSessionMigrationsOldVersion: Version?
    private var userSession: UserSessionProtocol? {
        didSet {
            userSessionObserver?.cancel()
            if let userSession {
                configureCallKitService()
                configureNotificationManager()
                observeUserSessionChanges()
                Task {
                    await resumeClientServices()
                    await appHooks.configure(with: userSession)
                }
            }
        }
    }
    
    private var authenticationFlowCoordinator: AuthenticationFlowCoordinator?
    private let appLockFlowCoordinator: AppLockFlowCoordinator
    // periphery:ignore - used to avoid deallocation
    private var appLockSetupFlowCoordinator: AppLockSetupFlowCoordinator?
    private var userSessionFlowCoordinator: UserSessionFlowCoordinator?
    private var softLogoutCoordinator: SoftLogoutScreenCoordinator?
    private var appDelegateObserver: AnyCancellable?
    private var userSessionObserver: AnyCancellable?
    private var clientProxyObserver: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    
    let windowManager: SecureWindowManagerProtocol
    let notificationManager: NotificationManagerProtocol

    // AGENT-PLATFORM: persisted queue of approval-decide POSTs
    // that failed at notification-action time. Drained on
    // applicationDidBecomeActive via approvalActionRunner.reconcile().
    // Nil only if the App Group isn't readable (mis-configured
    // entitlements); the action handler degrades to "do the POST
    // once, no retry queue" in that case.
    private let pendingApprovalActionStore: PendingApprovalActionStore?

    // AGENT-PLATFORM: backing impl for approve/reject lock-screen
    // actions. Captures `self` weakly via the resolveService
    // closure so the runner doesn't retain the AppCoordinator.
    private lazy var approvalActionRunner: ApprovalActionRunner = .init(resolveService: { [weak self] in self?.userSession?.agentPlatformService },
                                                                        pendingStore: pendingApprovalActionStore)

    // AGENT-PLATFORM (Brief 0073): public lookup of an invitation's state.
    private let inviteLinkResolver: InviteLinkResolverProtocol = InviteLinkResolver()

    private let appRouteURLParser: AppRouteURLParser
    
    private var storedAppRoute: AppRoute?
    @Consumable private var storedInlineReply: (roomID: String, message: String)?
    @Consumable private var storedRoomsToAwait: Set<String>?
    
    init(appDelegate: AppDelegate) {
        let appHooks = AppHooks()
        appHooks.setUp()
        
        // Override colours before we start building any UI components.
        appHooks.compoundHook.override(colors: Color.compound, uiColors: UIColor.compound)
        
        windowManager = WindowManager(appDelegate: appDelegate)
        let networkMonitor = NetworkMonitor()
        appMediator = AppMediator(windowManager: windowManager, networkMonitor: networkMonitor)
        
        guard let userDefaults = TrackedUserDefaults(suiteName: AppSettings.suiteName) else {
            fatalError("Catastrophic error retrieving user defaults for \(AppSettings.suiteName)")
        }
        let appSettings = appHooks.appSettingsHook.configure(AppSettings(store: userDefaults))
        appSettings.useLocalDevStackIfRequested() // AGENT-PLATFORM
        self.appSettings = appSettings
        
        targetConfiguration = Target.mainApp.configure(logLevel: appSettings.logLevel,
                                                       traceLogPacks: appSettings.traceLogPacks,
                                                       sentryURL: nil, // AGENT-PLATFORM (Brief 0078): no crash reporter.
                                                       rageshakeURL: appSettings.bugReportRageshakeURL,
                                                       appHooks: appHooks)
        
        let appName = InfoPlistReader.main.bundleDisplayName
        let appVersion = InfoPlistReader.main.bundleShortVersionString
        let appBuild = InfoPlistReader.main.bundleVersion
        MXLog.info("\(appName) \(appVersion) (\(appBuild))")
        
        if ProcessInfo.processInfo.environment["RESET_APP_SETTINGS"].map(Bool.init) == true {
            appSettings.resetAllSettings()
        }
        
        self.appDelegate = appDelegate
        self.appHooks = appHooks
        
        appRouteURLParser = AppRouteURLParser(appSettings: appSettings)
        
        // AGENT-PLATFORM (Brief 0078): Spiral links no analytics SDK (PostHog removed).
        analyticsService = AnalyticsService(client: DisabledAnalyticsClient(), appSettings: appSettings)
        
        userIndicatorController = UserIndicatorController()
        
        callKitService = CallKitService()
        
        navigationRootCoordinator = NavigationRootCoordinator()
        
        stateMachine = AppCoordinatorStateMachine()
        
        navigationRootCoordinator.setRootCoordinator(SplashScreenCoordinator())
        
        let keychainController = KeychainController(service: .sessions,
                                                    accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier)
        userSessionStore = UserSessionStore(keychainController: keychainController,
                                            appSettings: appSettings,
                                            analyticsService: analyticsService,
                                            appHooks: appHooks,
                                            networkMonitor: networkMonitor)
        
        let appLockService = AppLockService(keychainController: keychainController, appSettings: appSettings)
        let appLockNavigationCoordinator = NavigationRootCoordinator()
        appLockFlowCoordinator = AppLockFlowCoordinator(appLockService: appLockService,
                                                        navigationCoordinator: appLockNavigationCoordinator,
                                                        appSettings: appSettings)
        
        notificationManager = NotificationManager(notificationCenter: UNUserNotificationCenter.current(),
                                                  appSettings: appSettings)

        // AGENT-PLATFORM: pending-approval-actions queue. Lives in
        // App Group UserDefaults so the queue survives process
        // restarts and is reconciled on the next foreground.
        pendingApprovalActionStore = PendingApprovalActionStore(appGroupIdentifier: InfoPlistReader.main.appGroupIdentifier)
        
        bugReportService = BugReportService(rageshakeURLPublisher: appSettings.bugReportRageshakeURL.publisher,
                                            applicationID: appSettings.bugReportApplicationID,
                                            sdkGitSHA: sdkGitSha(),
                                            appHooks: appHooks)
        
        // AGENT-PLATFORM (Brief 0078): no Sentry to set up.
        analyticsService.startIfEnabled()
        
        windowManager.delegate = self
        
        notificationManager.delegate = self
        notificationManager.start()
        
        guard let currentVersion = Version(InfoPlistReader(bundle: .main).bundleShortVersionString) else {
            fatalError("The app's version number **must** use semver for migration purposes.")
        }
        
        if let previousVersion = appSettings.lastVersionLaunched.flatMap(Version.init) {
            performMigrationsIfNecessary(from: previousVersion, to: currentVersion)
        } else {
            // The app has been deleted since the previous run. Reset everything.
            wipeUserData(includingSettings: true)
        }
        appSettings.lastVersionLaunched = currentVersion.description
        
        setupStateMachine()
        
        observeApplicationState()
        observeAppLockChanges()
        
        registerBackgroundAppRefresh()
        
        callKitService.actions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                switch action {
                case .startCall(let roomID, let isVoiceCall):
                    self?.handleAppRoute(.call(roomID: roomID, isVoiceCall: isVoiceCall), windowType: nil)
                case .receivedIncomingCallRequest:
                    // When reporting a VoIP call through the CXProvider's `reportNewIncomingVoIPPushPayload`
                    // the UIApplication states don't change and services are neither started nor ran on
                    // a background task. Handle both manually here.
                    Task {
                        await self?.resumeClientServices()
                        self?.scheduleDelayedPauseServices()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
        
        windowManager.secondaryWindowsEnabled = !appLockService.isEnabled
        appLockService.isEnabledPublisher.sink { [weak windowManager] appLockEnabled in
            windowManager?.secondaryWindowsEnabled = !appLockEnabled
        }
        .store(in: &cancellables)
    }
    
    func start() {
        guard stateMachine.state == .initial else {
            MXLog.error("Received a start request when already started")
            return
        }
        
        guard userSessionStore.hasSessions else {
            stateMachine.processEvent(.startWithAuthentication)
            return
        }
        
        stateMachine.processEvent(.startWithExistingSession)
    }
    
    func toPresentable() -> AnyView {
        AnyView(navigationRootCoordinator.toPresentable()
            .environment(\.analyticsService, analyticsService)
            .onReceive(appSettings.appAppearancePublisher) { [weak self] appAppearance in
                guard let self else { return }
                
                windowManager.windows.forEach { window in
                    // Unfortunately .preferredColorScheme doesn't propagate properly throughout the app when changed
                    window.overrideUserInterfaceStyle = appAppearance.interfaceStyle
                }
            })
    }
    
    func handlePotentialPhishingAttempt(url: URL, openURLAction: @escaping (URL) -> Void) -> Bool {
        guard let confirmationParameters = url.confirmationParameters else {
            return false
        }
        navigationRootCoordinator.alertInfo = .init(id: .init(),
                                                    title: L10n.dialogConfirmLinkTitle,
                                                    message: L10n.dialogConfirmLinkMessage(confirmationParameters.displayString,
                                                                                           confirmationParameters.internalURL.absoluteString),
                                                    primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                                    secondaryButton: .init(title: L10n.actionContinue) { openURLAction(confirmationParameters.internalURL) })
        return true
    }
    
    func handleAppRoute(_ appRoute: AppRoute, windowType: SecondaryWindowType?) {
        Task {
            await asyncHandleAppRoute(appRoute, windowType: windowType)
        }
    }
    
    private func asyncHandleAppRoute(_ appRoute: AppRoute, windowType: SecondaryWindowType?) async {
        MXLog.info("Handling app route:  \(appRoute)")
        
        await resumeClientServices()
        
        if let windowType {
            windowManager.handleRoute(appRoute, windowType: windowType)
            return
        }
        
        var handled = false
        
        switch appRoute {
        case .accountProvisioningLink, .inviteLink:
            if let authenticationFlowCoordinator {
                authenticationFlowCoordinator.handleAppRoute(appRoute, animated: appMediator.appState == .active)
                handled = true
            }
        default:
            if let userSessionFlowCoordinator {
                userSessionFlowCoordinator.handleAppRoute(appRoute, animated: appMediator.appState == .active)
                handled = true
            }
        }
        
        if !handled {
            storedAppRoute = appRoute
        }
    }
    
    func handleDeepLink(_ url: URL, isExternalURL: Bool, windowType: SecondaryWindowType?) -> Bool {
        // Parse into an AppRoute to redirect these in a type safe way.
        
        if let route = appRouteURLParser.route(from: url) {
            switch route {
            case .accountProvisioningLink:
                handleAppRoute(route,
                               windowType: windowType)
            case .inviteLink(let link):
                // AGENT-PLATFORM (Brief 0073 / ADR-0008).
                handleInviteLink(link, windowType: windowType)
            case .oAuthCallback(let url):
                if stateMachine.state == .softLogout {
                    softLogoutCoordinator?.handleOAuthCallbackURL(url)
                } else {
                    authenticationFlowCoordinator?.handleOAuthCallbackURL(url)
                }
            case .userProfile(let userID):
                if isExternalURL {
                    handleAppRoute(route,
                                   windowType: windowType)
                } else {
                    handleAppRoute(.roomMemberDetails(userID: userID),
                                   windowType: windowType)
                }
            case .room(let roomID, let via):
                if isExternalURL {
                    handleAppRoute(route,
                                   windowType: windowType)
                } else {
                    handleAppRoute(.childRoom(roomID: roomID, via: via),
                                   windowType: windowType)
                }
            case .roomAlias(let alias):
                if isExternalURL {
                    handleAppRoute(route,
                                   windowType: windowType)
                } else {
                    handleAppRoute(.childRoomAlias(alias),
                                   windowType: windowType)
                }
            case .event(let eventID, let roomID, let via):
                if isExternalURL {
                    handleAppRoute(route,
                                   windowType: windowType)
                } else {
                    handleAppRoute(.childEvent(eventID: eventID, roomID: roomID, via: via),
                                   windowType: windowType)
                }
            case .eventOnRoomAlias(let eventID, let alias):
                if isExternalURL {
                    handleAppRoute(route,
                                   windowType: windowType)
                } else {
                    handleAppRoute(.childEventOnRoomAlias(eventID: eventID, alias: alias),
                                   windowType: windowType)
                }
            case .share(let payload):
                guard isExternalURL else {
                    MXLog.error("Received unexpected internal share route")
                    break
                }
                
                do {
                    try handleAppRoute(.share(payload.withDefaultTemporaryDirectory()),
                                       windowType: windowType)
                } catch {
                    MXLog.error("Failed moving payload out of the app group container: \(error)")
                }
            case .catalogTemplate:
                // AGENT-PLATFORM (decision 111): without this case `default`
                // swallows the link. Signed out it is stored and replayed.
                handleAppRoute(route, windowType: windowType)
            default:
                break
            }
            
            return true
        }
        
        return false
    }
    
    func handleUserActivity(_ userActivity: NSUserActivity) {
        guard let callDetails = Self.callDetails(for: userActivity) else {
            MXLog.error("Failed retrieving call details from user activity: \(userActivity.activityType)")
            return
        }
        
        MXLog.info("Starting call in room: \(callDetails.roomID)")
        handleAppRoute(.call(roomID: callDetails.roomID, isVoiceCall: callDetails.isVoiceCall), windowType: nil)
    }
    
    static func callDetails(for userActivity: NSUserActivity) -> (roomID: String, isVoiceCall: Bool)? {
        switch userActivity.interaction?.intent {
        case let intent as INStartCallIntent:
            return callDetails(for: intent)
        case let intent as INStartAudioCallIntent:
            return callDetails(contacts: intent.contacts, callRecord: nil, isVoiceCall: true)
        case let intent as INStartVideoCallIntent:
            return callDetails(contacts: intent.contacts, callRecord: nil, isVoiceCall: false)
        default:
            return nil
        }
    }

    static func callDetails(for intent: INStartCallIntent) -> (roomID: String, isVoiceCall: Bool)? {
        callDetails(contacts: intent.contacts,
                    callRecord: intent.callRecordToCallBack,
                    isVoiceCall: intent.callCapability != .videoCall)
    }
    
    private static func callDetails(contacts: [INPerson]?,
                                    callRecord: INCallRecord?,
                                    isVoiceCall: Bool) -> (roomID: String, isVoiceCall: Bool)? {
        let contact = contacts?.first ?? callRecord?.participants?.first
        let identifiers = [contact?.customIdentifier,
                           contact?.personHandle?.value,
                           callRecord?.identifier].compactMap { $0 }
        // Outgoing calls hand CallKit the room ID itself, incoming ones the caller's,
        // so fall back to the routing table only when the handle isn't a room.
        let roomID = identifiers.first(where: MatrixEntityRegex.isMatrixRoomID)
            ?? identifiers.compactMap(CallKitRoomRouting.roomID(for:)).first

        guard let roomID else { return nil }

        return (roomID, isVoiceCall)
    }
    
    // MARK: - AuthenticationFlowCoordinatorDelegate
    
    func authenticationFlowCoordinator(didLoginWithSession userSession: UserSessionProtocol) {
        self.userSession = userSession
        authenticationFlowCoordinator = nil
        stateMachine.processEvent(.createdUserSession)
    }
    
    // MARK: - WindowManagerDelegate
    
    func windowManagerDidConfigureWindows(_ windowManager: SecureWindowManagerProtocol) {
        windowManager.alternateWindow.rootViewController = UIHostingController(rootView: appLockFlowCoordinator.toPresentable())
        userIndicatorController.window = windowManager.overlayWindow
    }
    
    // MARK: - NotificationManagerDelegate
    
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    func unregisterForRemoteNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }
    
    func shouldDisplayInAppNotification(content: UNNotificationContent) -> Bool {
        guard let roomID = content.roomID else {
            return true
        }
        guard let userSessionFlowCoordinator else {
            // there is not a user session yet
            return false
        }
        return !userSessionFlowCoordinator.isDisplayingRoomScreen(withRoomID: roomID)
    }
    
    func notificationTapped(content: UNNotificationContent) async {
        MXLog.info("Tapped Notification")
        
        // AGENT-PLATFORM: an approval or verification push opens its decide
        // screen on the Agents tab rather than a chat room.
        if let agentPlatformRoute = content.agentPlatformRoute {
            handleAppRoute(agentPlatformRoute, windowType: nil)
            return
        }

        guard let roomID = content.roomID,
              content.receiverID != nil else {
            return
        }
        
        // AGENT-PLATFORM (Brief 0066, § 5.82): a game's ping opens the room on
        // the post it came from, as a link to a message does.
        if let spiralPostRoute = content.spiralPostRoute {
            analyticsService.signpost.startTransaction(.notificationToMessage)
            handleAppRoute(spiralPostRoute, windowType: nil)
            return
        }
        
        let eventID = appSettings.focusEventOnNotificationTap ? content.eventID : nil
        if content.categoryIdentifier == NotificationConstants.Category.invite {
            if let userSession {
                userSession.clientProxy.roomsToAwait.insert(roomID)
            } else {
                storedRoomsToAwait = [roomID]
            }
            handleAppRoute(.room(roomID: roomID, via: []), windowType: nil)
        } else if appSettings.threadsEnabled, let threadRootEventID = content.threadRootEventID {
            handleAppRoute(.thread(roomID: roomID, threadRootEventID: threadRootEventID, focusEventID: eventID), windowType: nil)
        } else if let eventID {
            // Only track main timeline event deeplinking
            analyticsService.signpost.startTransaction(.notificationToMessage)
            handleAppRoute(.event(eventID: eventID, roomID: roomID, via: []), windowType: nil)
        } else {
            handleAppRoute(.room(roomID: roomID, via: []), windowType: nil)
        }
    }
    
    func handleInlineReply(_ service: NotificationManagerProtocol, content: UNNotificationContent, replyText: String) async {
        MXLog.info("Handle notification reply")
        
        guard let roomID = content.roomID else {
            return
        }
        
        if userSession == nil {
            // Store the data so it can be used after the session is established
            storedInlineReply = (roomID, replyText)
            return
        }
        
        await processInlineReply(roomID: roomID, replyText: replyText)
    }

    // AGENT-PLATFORM: thin wrapper that forwards to
    // `ApprovalActionRunner`. Heavy lifting (background task,
    // session-wait, retry queue, failure notifications) lives
    // in the runner to keep this file under SwiftLint's
    // type_body_length cap.
    func handleApprovalAction(_ service: NotificationManagerProtocol,
                              content: UNNotificationContent,
                              decision: ApprovalDecision) async {
        guard let approvalID = content.agentApprovalID else {
            MXLog.error("handleApprovalAction: notification missing agentApprovalID")
            return
        }
        await approvalActionRunner.run(approvalID: approvalID,
                                       decision: decision,
                                       userInfo: content.userInfo,
                                       threadIdentifier: content.threadIdentifier)
    }
    
    // MARK: - Private
    
    /// Perform any required migrations for the app to function correctly.
    private func performMigrationsIfNecessary(from oldVersion: Version, to newVersion: Version) {
        guard oldVersion != newVersion else { return }
        
        // Be tidy and clean up after ourselves every now and then (because Apple is lazy)
        clearTemporaryDirectories()
        
        MXLog.info("The app was upgraded from \(oldVersion) to \(newVersion)")
        
        if oldVersion < Version(1, 6, 0) {
            MXLog.info("Migrating to v1.6.0, marking identity confirmation onboarding as ran.")
            if !userSessionStore.userIDs.isEmpty {
                appSettings.hasRunIdentityConfirmationOnboarding = true
                appSettings.hasRunNotificationPermissionsOnboarding = true
            }
        }
        
        if oldVersion < Version(1, 6, 7) {
            Tracing.deleteLogFiles(in: Tracing.legacyLogsDirectory)
            MXLog.info("Migrating to v1.6.7, log files have been wiped")
        }
        
        if oldVersion < Version(25, 7, 4) {
            Tracing.migrateLogFiles()
            MXLog.info("Migrating to version 25.07.4, log files have been moved.")
        }
        
        // Store the old version to run additional migrations on the user session once it has been set up.
        userSessionMigrationsOldVersion = oldVersion
    }
    
    private func performUserSessionMigrations(_ userSession: UserSessionProtocol) async {
        guard let oldVersion = userSessionMigrationsOldVersion else { return }
        
        MXLog.info("Migrating user session from \(oldVersion)")
        
        MXLog.info("Performing client store optimizations.")
        await userSession.clientProxy.optimizeStores()
        MXLog.info("Finished optimizing client stores.")
        
        if oldVersion < Version(25, 6, 0) {
            MXLog.info("Migrating to version 25.06.0, migrating timeline media settings to account data.")
            performSettingsToAccountDataMigration(userSession: userSession)
        }
        
        if oldVersion < Version(25, 9, 2) {
            MXLog.info("Migrating to version 25.09.2, triggering sync to ensure m.space state is up to date.")
            await userSession.clientProxy.expireSyncSessions()
        }
        
        if oldVersion < Version(25, 10, 0) {
            MXLog.info("Migrating to version 25.10.0, showing new sound banner to existing user.")
            appSettings.hasSeenNewSoundBanner = false
        }
        
        if oldVersion < Version(26, 07, 3) {
            MXLog.info("Migrating to version 26.07.3, marking the app as previously signed in.")
            appSettings.hasSignedInBefore = true
        }
        
        userSessionMigrationsOldVersion = nil
    }
    
    /// This could be removed once the adoption of 25.06.x is widespread.
    private func performSettingsToAccountDataMigration(userSession: UserSessionProtocol) {
        guard let userDefaults = UserDefaults(suiteName: InfoPlistReader.main.appGroupIdentifier) else {
            return
        }
        
        let hideInviteAvatars = userDefaults.value(forKey: "hideInviteAvatars") as? Bool
        let timelineMediaVisibility = userDefaults
            .data(forKey: "timelineMediaVisibility")
            .flatMap {
                try? JSONDecoder().decode(TimelineMediaVisibility.self, from: $0)
            }
        let hideTimelineMedia = userDefaults.value(forKey: "hideTimelineMedia") as? Bool
        
        guard hideInviteAvatars != nil || timelineMediaVisibility != nil || hideTimelineMedia != nil else {
            // No migration needed, no local settings found.
            return
        }
        
        Task {
            switch await userSession.clientProxy.fetchMediaPreviewConfiguration() {
            case let .success(config):
                guard config == nil else {
                    // Found a server configuration, no need to migrate.
                    userDefaults.removeObject(forKey: "hideInviteAvatars")
                    userDefaults.removeObject(forKey: "timelineMediaVisibility")
                    userDefaults.removeObject(forKey: "hideTimelineMedia")
                    return
                }
                
                if let hideInviteAvatars, case .success = await userSession.clientProxy.setHideInviteAvatars(hideInviteAvatars) {
                    userDefaults.removeObject(forKey: "hideInviteAvatars")
                }
                
                if let timelineMediaVisibility, case .success = await userSession.clientProxy.setTimelineMediaVisibility(timelineMediaVisibility) {
                    userDefaults.removeObject(forKey: "timelineMediaVisibility")
                } else if let hideTimelineMedia, case .success = await userSession.clientProxy.setTimelineMediaVisibility(hideTimelineMedia ? .never : .always) {
                    userDefaults.removeObject(forKey: "hideTimelineMedia")
                }
            case let .failure(error):
                MXLog.error("Could not perform migration, failed to fetch media preview config: \(error)")
                return
            }
        }
    }
    
    /// Clears the keychain, app support directory etc ready for a fresh use.
    /// - Parameter includingSettings: Whether to additionally wipe the user's app settings too.
    private func wipeUserData(includingSettings: Bool = false) {
        if includingSettings {
            appSettings.resetAllSettings()
            appLockFlowCoordinator.appLockService.disable()
        }
        userSessionStore.reset()
    }
    
    /// Manually cleans up any files in the app group's `tmp` directory.
    ///
    /// **Note:** If there is a single file we consider it to be an active share payload and ignore it.
    private func clearTemporaryDirectories() {
        // First get rid of everything in the App's temporary directory
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: URL.temporaryDirectory, includingPropertiesForKeys: nil, options: [])
            
            fileURLs.forEach { url in
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    MXLog.warning("Failed to remove file from temporary directory: \(error)")
                }
            }
        } catch {
            MXLog.warning("Failed to enumerate temporary directory: \(error)")
        }
        
        // Manual clean to handle the potential case where the app crashes before moving a shared file.
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: URL.appGroupTemporaryDirectory, includingPropertiesForKeys: nil, options: [])
            
            guard fileURLs.count > 1 else {
                return // If there is only a single item in here, there's likely a pending share payload that is yet to be processed.
            }
            
            for url in fileURLs {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    MXLog.warning("Failed to remove file from app group temporary directory: \(error)")
                }
            }
        } catch {
            MXLog.warning("Failed to enumerate app group temporary directory: \(error)")
        }
    }
    
    private func setupStateMachine() {
        stateMachine.addTransitionHandler { [weak self] context in
            guard let self else { return }
            
            switch (context.fromState, context.event, context.toState) {
            case (.initial, .startWithAuthentication, .signedOut):
                startAuthentication()
            case (.signedOut, .createdUserSession, .signedIn):
                setupUserSession(isNewLogin: true)
            case (.initial, .startWithExistingSession, .restoringSession):
                restoreUserSession()
            case (.restoringSession, .failedRestoringSession, .signedOut):
                showLoginErrorToast()
                presentSplashScreen()
            case (.restoringSession, .createdUserSession, .signedIn):
                setupUserSession(isNewLogin: false)
                
            case (.signingOut, .signOut, .signingOut):
                // We can ignore signOut when already in the process of signing out,
                // such as the SDK sending an authError due to token invalidation.
                break
            case (_, .signOut(let isSoft, _), .signingOut):
                logout(isSoft: isSoft)
            case (.signingOut(_, let disableAppLock), .completedSigningOut, .signedOut):
                presentSplashScreen(isSoftLogout: false, disableAppLock: disableAppLock)
            case (.signingOut(_, let disableAppLock), .showSoftLogout, .softLogout):
                presentSplashScreen(isSoftLogout: true, disableAppLock: disableAppLock)
            case (.signedIn, .clearCache, .initial):
                clearCache()
            default:
                fatalError("Unknown transition: \(context)")
            }
        }
        
        stateMachine.addErrorHandler { context in
            if context.fromState == context.toState {
                MXLog.error("Failed transition from equal states: \(context.fromState)")
            } else {
                fatalError("Failed transition with context: \(context)")
            }
        }
    }
    
    private func restoreUserSession() {
        Task {
            switch await userSessionStore.restoreUserSession() {
            case .success(let userSession):
                await self.performUserSessionMigrations(userSession)
                self.userSession = userSession
                stateMachine.processEvent(.createdUserSession)
            case .failure:
                MXLog.error("Failed to restore an existing session.")
                stateMachine.processEvent(.failedRestoringSession)
            }
        }
    }
    
    private func startAuthentication() {
        let encryptionKeyProvider = EncryptionKeyProvider()
        let classicAppManager = ClassicAppManager()
        let authenticationService = AuthenticationService(userSessionStore: userSessionStore,
                                                          encryptionKeyProvider: encryptionKeyProvider,
                                                          classicAppManager: classicAppManager,
                                                          appSettings: appSettings,
                                                          appHooks: appHooks)
        Task { await authenticationService.setupClassicAppAccountState() }
        
        let coordinator = AuthenticationFlowCoordinator(authenticationService: authenticationService,
                                                        bugReportService: bugReportService,
                                                        navigationRootCoordinator: navigationRootCoordinator,
                                                        appMediator: appMediator,
                                                        appSettings: appSettings,
                                                        appHooks: appHooks,
                                                        userIndicatorController: userIndicatorController)
        coordinator.delegate = self
        
        authenticationFlowCoordinator = coordinator
        coordinator.start()
        
        if storedAppRoute?.isAuthenticationRoute == true,
           let storedAppRoute = storedAppRoute.take() {
            coordinator.handleAppRoute(storedAppRoute, animated: false)
        }
    }
    
    // MARK: - Invite links (Brief 0073 / ADR-0008)
    
    // AGENT-PLATFORM: a tapped `spiral.md/join/{token}`. Logged out, the
    // invitation is remembered for the OAuth round-trip and the start
    // screen says who is inviting; logged in, the link is just a way to
    // reach the inviter — their profile opens, no seat is touched.
    private func handleInviteLink(_ link: SpiralInviteLink, windowType: SecondaryWindowType?) {
        if userSessionFlowCoordinator != nil {
            Task {
                switch await inviteLinkResolver.resolve(link) {
                case .success(.valid(let inviter?)):
                    handleAppRoute(.userProfile(userID: inviter.mxid), windowType: windowType)
                case .success:
                    userIndicatorController.submitIndicator(UserIndicator(title: UntranslatedL10n.inviteLinkOpenedWhileSignedIn, icon: \.userAdd))
                case .failure:
                    userIndicatorController.submitIndicator(UserIndicator(title: L10n.errorUnknown, icon: \.close))
                }
            }
            return
        }
        
        // Remember the token first so the banner and the OAuth URL have it
        // even if the lookup below is slow or fails (a campaign token has
        // no inviter to show anyway).
        if appSettings.pendingInvite?.token != link.token {
            appSettings.pendingInvite = PendingInvite(token: link.token)
        }
        handleAppRoute(.inviteLink(link), windowType: windowType)
        
        Task {
            let resolution = await inviteLinkResolver.resolve(link)
            guard appSettings.pendingInvite?.token == link.token else { return }
            switch resolution {
            case .success(.valid(let inviter)):
                appSettings.pendingInvite = PendingInvite(token: link.token,
                                                          inviterDisplayName: inviter?.displayName,
                                                          inviterUserID: inviter?.mxid)
            case .success:
                // Dead link: no banner, no token on the OAuth URL.
                appSettings.pendingInvite = nil
            case .failure:
                break // Could not check; keep it, identity-login decides.
            }
        }
    }
    
    // AGENT-PLATFORM (Brief 0073): the first session after arriving by
    // invitation opens the welcome screen — who invited you and «Message
    // <name>», the DM made by this client (ADR-0082). The bare inviter
    // profile it replaces did not say why it was there. The inviter's
    // assistant has meanwhile told them who joined (the referral notice).
    private func offerInviterAfterLogin() {
        guard let pendingInvite = appSettings.pendingInvite else { return }
        appSettings.pendingInvite = nil
        
        guard let inviterUserID = pendingInvite.inviterUserID,
              inviterUserID != userSession?.clientProxy.userID else { return }
        userSessionFlowCoordinator?.presentInviteWelcome(inviterUserID: inviterUserID)
    }
    
    private func runPostSessionSetupTasks() async {
        guard let userSession, let userSessionFlowCoordinator else {
            fatalError("User session not setup")
        }
        
        if let storedRoomsToAwait {
            userSession.clientProxy.roomsToAwait = storedRoomsToAwait
        }
        
        if storedAppRoute?.isAuthenticationRoute == false,
           let storedAppRoute = storedAppRoute.take() {
            userSessionFlowCoordinator.handleAppRoute(storedAppRoute, animated: false)
            // The invitation was for a registration that is now behind us.
            appSettings.pendingInvite = nil
        } else {
            offerInviterAfterLogin()
        }
        
        if let storedInlineReply {
            await processInlineReply(roomID: storedInlineReply.roomID, replyText: storedInlineReply.message)
        }
    }
    
    private func startAuthenticationSoftLogout() {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        Task {
            let credentials = SoftLogoutScreenCredentials(userID: userSession.clientProxy.userID,
                                                          homeserverName: userSession.clientProxy.homeserver,
                                                          userDisplayName: userSession.clientProxy.userProfilePublisher.value.displayName ?? "",
                                                          deviceID: userSession.clientProxy.deviceID)
            
            let authenticationService = AuthenticationService(userSessionStore: userSessionStore,
                                                              encryptionKeyProvider: EncryptionKeyProvider(),
                                                              classicAppManager: ClassicAppManager(),
                                                              appSettings: appSettings,
                                                              appHooks: appHooks)
            _ = await authenticationService.configure(for: userSession.clientProxy.homeserver, flow: .login)
            
            let parameters = SoftLogoutScreenCoordinatorParameters(authenticationService: authenticationService,
                                                                   credentials: credentials,
                                                                   keyBackupNeeded: false,
                                                                   appMediator: appMediator,
                                                                   appSettings: appSettings,
                                                                   appHooks: appHooks,
                                                                   userIndicatorController: userIndicatorController)
            let coordinator = SoftLogoutScreenCoordinator(parameters: parameters)
            self.softLogoutCoordinator = coordinator
            coordinator.actions
                .sink { [weak self] action in
                    guard let self else { return }
                    
                    switch action {
                    case .signedIn(let session):
                        self.userSession = session
                        self.softLogoutCoordinator = nil
                        stateMachine.processEvent(.createdUserSession)
                    case .clearAllData:
                        self.softLogoutCoordinator = nil
                        stateMachine.processEvent(.signOut(isSoft: false, disableAppLock: false))
                    }
                }
                .store(in: &cancellables)
            
            navigationRootCoordinator.setRootCoordinator(coordinator)
        }
    }
    
    private func setupUserSession(isNewLogin: Bool) {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        // AGENT-PLATFORM (Brief 0078): the hashed homeserver tag was for Sentry.
        if !isNewLogin {
            analyticsService.signpost.startTransaction(.cachedRoomList)
        }
        
        let flowParameters = CommonFlowParameters(userSession: userSession,
                                                  bugReportService: bugReportService,
                                                  callKitService: callKitService,
                                                  timelineControllerFactory: TimelineControllerFactory(appSettings: appSettings),
                                                  emojiProvider: EmojiProvider(appSettings: appSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: appMediator,
                                                  appSettings: appSettings,
                                                  appHooks: appHooks,
                                                  analytics: analyticsService,
                                                  userIndicatorController: userIndicatorController,
                                                  notificationManager: notificationManager,
                                                  stateMachineFactory: StateMachineFactory())
        
        let userSessionFlowCoordinator = UserSessionFlowCoordinator(isNewLogin: isNewLogin,
                                                                    navigationRootCoordinator: navigationRootCoordinator,
                                                                    appLockService: appLockFlowCoordinator.appLockService,
                                                                    flowParameters: flowParameters)
        
        userSessionFlowCoordinator.actionsPublisher
            .sink { [weak self] action in
                guard let self else { return }
                
                switch action {
                case .logout:
                    stateMachine.processEvent(.signOut(isSoft: false, disableAppLock: false))
                case .clearCache:
                    stateMachine.processEvent(.clearCache)
                case .forceLogout:
                    stateMachine.processEvent(.signOut(isSoft: false, disableAppLock: true))
                }
            }
            .store(in: &cancellables)
        
        userSessionFlowCoordinator.start()
        
        self.userSessionFlowCoordinator = userSessionFlowCoordinator
        
        Task {
            await runPostSessionSetupTasks()
        }
    }
    
    private func logout(isSoft: Bool) {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        windowManager.closeAllSecondaryWindows()
        // AGENT-PLATFORM (Brief 0073): an invitation never outlives the
        // session it was accepted into.
        appSettings.pendingInvite = nil
        
        showLoadingIndicator()
        
        Task { await pauseClientServices(isBackgroundTask: false) }
        userSessionFlowCoordinator?.stop()
        
        guard !isSoft else {
            stateMachine.processEvent(.showSoftLogout)
            hideLoadingIndicator()
            return
        }
        
        // The user will log out, clear any existing notifications and unregister from receving new ones
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().setBadgeCount(0)
        
        unregisterForRemoteNotifications()
        
        Task {
            // First log out from the server
            await userSession.clientProxy.logout()
            
            // Regardless of the result, clear user data
            userSessionStore.logout(userSession: userSession)
            tearDownUserSession()
            
            appSettings.resetSessionSpecificSettings()
            appSettings.mapTilerSettings.reset()
            appHooks.remoteSettingsHook.reset(appSettings)
            // The CallKit Recents routing table belongs to the account that
            // built it (audit W6-5-6).
            CallKitRoomRouting.clearAll()
            
            // Reset analytics
            analyticsService.optOut()
            analyticsService.resetConsentState()
            
            stateMachine.processEvent(.completedSigningOut)
            
            hideLoadingIndicator()
        }
    }
    
    private func tearDownUserSession() {
        userIndicatorController.retractAllIndicators()
        
        userSession = nil
        
        userSessionFlowCoordinator = nil
        
        notificationManager.setUserSession(nil)
    }
    
    private func presentSplashScreen(isSoftLogout: Bool = false, disableAppLock: Bool = false) {
        navigationRootCoordinator.setRootCoordinator(SplashScreenCoordinator())
        
        if isSoftLogout {
            startAuthenticationSoftLogout()
        } else {
            startAuthentication()
        }
        
        if disableAppLock {
            Task {
                // Ensure the navigation stack has settled.
                try? await Task.sleep(for: .milliseconds(500))
                appLockFlowCoordinator.appLockService.disable()
                windowManager.switchToMain()
            }
        }
    }
    
    private func configureCallKitService() {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        callKitService.setClientProxy(userSession.clientProxy)
    }
    
    private func configureNotificationManager() {
        notificationManager.setUserSession(userSession)
        
        appDelegateObserver = appDelegate.callbacks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callback in
                switch callback {
                case .registeredNotifications(let deviceToken):
                    Task { await self?.notificationManager.register(with: deviceToken) }
                case .failedToRegisteredNotifications(let error):
                    self?.notificationManager.registrationFailed(with: error)
                }
            }
    }
    
    private func observeUserSessionChanges() {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        userSessionObserver = userSession.callbacks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callback in
                guard let self else { return }
                switch callback {
                case .didReceiveAuthError(let isSoftLogout):
                    stateMachine.processEvent(.signOut(isSoft: isSoftLogout, disableAppLock: false))
                }
            }
    }
    
    private func observeAppLockChanges() {
        appLockFlowCoordinator.actions.sink { [weak self] action in
            guard let self else { return }
            switch action {
            case .lockApp:
                windowManager.switchToAlternate()
            case .unlockApp:
                windowManager.switchToMain()
            case .forceLogout:
                stateMachine.processEvent(.signOut(isSoft: false, disableAppLock: true))
            }
        }
        .store(in: &cancellables)
    }
    
    private func clearCache() {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        showLoadingIndicator()
        
        navigationRootCoordinator.setRootCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: appSettings.hideBrandChrome))
        
        Task { await pauseClientServices(isBackgroundTask: false) }
        userSessionFlowCoordinator?.stop()
        
        // Allow for everything to deallocate properly
        Task {
            await userSession.clientProxy.clearCaches()
            stateMachine.processEvent(.startWithExistingSession)
            hideLoadingIndicator()
        }
    }
    
    private func processInlineReply(roomID: String, replyText: String) async {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        guard case let .joined(roomProxy) = await userSession.clientProxy.roomForIdentifier(roomID) else {
            MXLog.error("Tried to reply in an unjoined room: \(roomID)")
            return
        }
        
        switch await roomProxy.timeline.sendMessage(replyText,
                                                    html: nil,
                                                    inReplyToEventID: nil,
                                                    intentionalMentions: .empty) {
        case .success:
            break
        default:
            await notificationManager.showLocalNotification(with: "⚠️ " + L10n.commonError,
                                                            subtitle: L10n.errorSomeMessagesHaveNotBeenSent)
        }
    }
    
    // MARK: Toasts and loading indicators
    
    private static let loadingIndicatorIdentifier = "\(AppCoordinator.self)-Loading"
    
    private func showLoadingIndicator() {
        userIndicatorController.submitIndicator(UserIndicator(id: Self.loadingIndicatorIdentifier,
                                                              type: .modal,
                                                              title: L10n.commonLoading,
                                                              persistent: true))
    }
    
    private func hideLoadingIndicator() {
        userIndicatorController.retractIndicatorWithId(Self.loadingIndicatorIdentifier)
    }
    
    private func showLoginErrorToast() {
        userIndicatorController.submitIndicator(UserIndicator(title: "Failed logging in"))
    }
    
    // MARK: - Application State
    
    private func pauseClientServices(isBackgroundTask: Bool) async {
        if isBackgroundTask, UIApplication.shared.applicationState == .active {
            // Attempt to pause the background task services cleanly, only if the app not already running
            return
        }
        
        await userSession?.clientProxy.pauseServices()
        clientProxyObserver = nil
    }
    
    private func resumeClientServices() async {
        guard let userSession else { return }
        
        analyticsService.signpost.startTransaction(.upToDateRoomList)
        
        await userSession.clientProxy.resumeServices()
        
        guard clientProxyObserver == nil else {
            return
        }
        
        clientProxyObserver = userSession.clientProxy
            .loadingStatePublisher
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                let toastIdentifier = "StaleDataIndicator"
                guard let self else { return }
                
                switch state {
                case .loading:
                    if self.userSession?.clientProxy.homeserverReachabilityPublisher.value == .reachable,
                       self.appMediator.networkMonitor.reachabilityPublisher.value == .reachable {
                        self.userIndicatorController.submitIndicator(.init(id: toastIdentifier, type: .toast(progress: .indeterminate), title: L10n.commonSyncing, persistent: true))
                    }
                case .notLoading:
                    self.analyticsService.signpost.finishTransaction(.upToDateRoomList)
                    self.userIndicatorController.retractIndicatorWithId(toastIdentifier)
                }
            }
    }
    
    private func observeApplicationState() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillTerminate),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didChangeContentSizeCategory),
                                               name: UIContentSizeCategory.didChangeNotification,
                                               object: nil)
    }
    
    @objc
    private func didChangeContentSizeCategory() {
        AttributedStringBuilder.invalidateCaches()
    }
    
    @objc
    private func applicationWillTerminate() {
        MXLog.info("Application will terminate")
        Task { await pauseClientServices(isBackgroundTask: false) }
    }
    
    @objc
    private func applicationDidEnterBackground() {
        MXLog.info("Application did enter background")
        
        scheduleDelayedPauseServices()
        scheduleBackgroundAppRefresh()
    }
    
    @objc
    private func applicationWillResignActive() {
        MXLog.info("Application will resign active")
    }
    
    private func scheduleDelayedPauseServices() {
        guard backgroundTask == nil else {
            return
        }
        
        backgroundTask = appMediator.beginBackgroundTask {
            MXLog.info("Background task is about to expire.")
            
            // We're intentionally strongly retaining self here to an EXC_BAD_ACCESS
            // `backgroundTask` will be eventually released in `endActiveBackgroundTask`
            // https://sentry.tools.element.io/organizations/element/issues/4477794/events/9cfd04e4d045440f87498809cf718de5/
            Task { @MainActor in
                await self.pauseClientServices(isBackgroundTask: true)
                self.endActiveBackgroundTask()
            }
        }
    }
    
    @objc
    private func applicationWillEnterForeground() {
        MXLog.info("Application will enter foreground")
        endActiveBackgroundTask()
        Task {
            await resumeClientServices()
        }
        // AGENT-PLATFORM: replay any approval decide-POSTs that
        // failed while the app was in the background. Idempotent
        // — successful retries clear the queue; 409 conflicts are
        // treated as success-equivalent.
        Task { await self.approvalActionRunner.reconcile() }
    }
    
    @objc
    private func applicationDidBecomeActive() {
        MXLog.info("Application did become active")
        
        // AGENT-PLATFORM: the icon badge is written by the NSE from the
        // homeserver's push count and by nothing else, so it survives
        // untouched after the user has read everything — the reported
        // "badge says 2, there is nothing unread" — until some later push
        // happens to carry a different number. Recompute from the room list
        // the moment the user looks at the phone, which is when a wrong
        // number is actually visible.
        guard let userSession else { return }
        Task {
            let roomSummaries = userSession.clientProxy.staticRoomSummaryProvider.roomListPublisher.value
            await notificationManager.updateBadgeCount(with: roomSummaries)
        }
    }
    
    private func endActiveBackgroundTask() {
        guard let backgroundTask else {
            return
        }
        
        MXLog.info("Ending background task.")
        appMediator.endBackgroundTask(backgroundTask)
        self.backgroundTask = nil
    }
    
    // MARK: Background app refresh
    
    private func registerBackgroundAppRefresh() {
        let result = BGTaskScheduler.shared.register(forTaskWithIdentifier: appSettings.backgroundAppRefreshTaskIdentifier, using: .main) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else {
                MXLog.error("Invalid background app refresh configuration")
                return
            }
            
            Task {
                await self?.handleBackgroundAppRefresh(task)
            }
        }
        
        MXLog.info("Register background app refresh with result: \(result)")
    }
    
    private func scheduleBackgroundAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: appSettings.backgroundAppRefreshTaskIdentifier)
        
        // We have other background tasks that keep the app alive
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            MXLog.info("Successfully scheduled background app refresh task")
        } catch {
            MXLog.error("Failed scheduling background app refresh with error :\(error)")
        }
    }
    
    private var backgroundRefreshSyncObserver: AnyCancellable?
    private func handleBackgroundAppRefresh(_ task: BGAppRefreshTask) async {
        MXLog.info("Started background app refresh")
        
        // This is important for the app to keep refreshing in the background
        scheduleBackgroundAppRefresh()
        
        // We have a lot of crashes stemming here which we previously believed were caused by pauseServices not being
        // async on the client proxy side. We have now realised that will likely not fix anything but we also noticed
        // this does not crash on the main thread, even though the whole AppCoordinator is on the Main actor. As such,
        // we hop onto the main actor explicitly before pausing.
        // https://sentry.tools.element.io/organizations/element/issues/4477794/
        // BGTask isn't annotated but is documented as thread-safe, with
        // setTaskCompleted(success:) being callable from any thread.
        nonisolated(unsafe) let task = task
        task.expirationHandler = { @Sendable [weak self] in
            MXLog.info("Background app refresh task is about to expire.")
            
            Task { @MainActor in
                await self?.pauseClientServices(isBackgroundTask: true)
                MXLog.info("Marking Background app refresh task as complete.")
                task.setTaskCompleted(success: true)
            }
        }
        
        guard let userSession else {
            return
        }
        
        // Configure the background-refresh sync to carry set_presence=offline so it doesn't mark the
        // user online or idle. Note: If already online/idle then setting offline shouldn't override that.
        _ = await userSession.clientProxy.configurePresence(.offline, sendImmediately: false)
        
        await resumeClientServices()
        
        // Be a good citizen, run for a max of 10 SS responses or 10 seconds
        // An SS request will time out after 30 seconds if no new data is available
        backgroundRefreshSyncObserver = userSession.clientProxy
            .actionsPublisher
            .filter(\.isSyncUpdate)
            .collect(.byTimeOrCount(DispatchQueue.main, .seconds(10), 10))
            .sink { [weak self] _ in
                guard let self else { return }
                MXLog.info("Background app refresh finished")
                backgroundRefreshSyncObserver?.cancel()
                
                // Make sure we stop the sync loop, otherwise the ongoing request is immediately
                // handled the next time the app refreshes, which can trigger timeout failures.
                Task {
                    await self.pauseClientServices(isBackgroundTask: true)
                    MXLog.info("Marking Background app refresh task as complete.")
                    task.setTaskCompleted(success: true)
                }
            }
    }
}
