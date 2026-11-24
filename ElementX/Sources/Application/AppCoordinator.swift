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
    private let userSessionManager: UserSessionManagerProtocol
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
    
    private var backgroundRefreshSyncObserver: AnyCancellable?
    
    /// AGENT-PLATFORM (1.0.3): set when this launch updated the app or ran upstream migrations; each account migrates from its own baseline.
    private var userSessionMigrationsOldVersion: Version?
    /// The accounts migrated since launch, so restoring one again (e.g. after clearing the cache) never migrates it twice.
    private var migratedUserIDs: Set<String> = []
    /// Restores the signed in accounts. Cancelled when signing out or clearing the cache.
    private var restorationTask: Task<Void, Never>?
    private var userSession: UserSessionProtocol? {
        userSessionManager.activeSession
    }
    
    private var authenticationFlowCoordinator: AuthenticationFlowCoordinator?
    private let appLockFlowCoordinator: AppLockFlowCoordinator
    // periphery:ignore - used to avoid deallocation
    private var appLockSetupFlowCoordinator: AppLockSetupFlowCoordinator?
    private var userSessionFlowCoordinator: UserSessionFlowCoordinator?
    private var softLogoutCoordinator: SoftLogoutScreenCoordinator?
    private var appDelegateObserver: AnyCancellable?
    /// Becomes `true` once the app is no longer waiting on a session restore, whatever the outcome.
    private let isSessionRestoredSubject = CurrentValueSubject<Bool, Never>(false)
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
    /// The account of a notification tapped while restoring, its route only opens once that account is the active one.
    @Consumable private var storedAppRouteReceiverID: String?
    /// A reply made from a notification before its account was live.
    private var storedInlineReply: PendingInlineReplyDetails?
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
        
        // AGENT-PLATFORM (Brief 0067): CallKit + native MatrixRTC replace ElementCallService (ADR-0079).
        callKitService = CallKitService()
        
        navigationRootCoordinator = NavigationRootCoordinator()
        
        stateMachine = AppCoordinatorStateMachine()
        
        navigationRootCoordinator.setRootCoordinator(SplashScreenCoordinator())
        
        let keychainController = KeychainController(service: .sessions,
                                                    accessGroup: InfoPlistReader.main.keychainAccessGroupIdentifier)
        let userSessionStore = UserSessionStore(keychainController: keychainController,
                                                appSettings: appSettings,
                                                analyticsService: analyticsService,
                                                appHooks: appHooks,
                                                networkMonitor: networkMonitor)
        notificationManager = NotificationManager(notificationCenter: UNUserNotificationCenter.current(), appSettings: appSettings)
        userSessionManager = UserSessionManager(userSessionStore: userSessionStore, appSettings: appSettings, notificationManager: notificationManager, liveLocationManager: LiveLocationManager(appSettings: appSettings))
        
        let appLockService = AppLockService(keychainController: keychainController, appSettings: appSettings)
        let appLockNavigationCoordinator = NavigationRootCoordinator()
        appLockFlowCoordinator = AppLockFlowCoordinator(appLockService: appLockService,
                                                        navigationCoordinator: appLockNavigationCoordinator,
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
        
        configureNotificationManager()
        
        // AGENT-PLATFORM (Brief 0086): taken before the migrations, as a first launch's wipe clears the App Group's
        // defaults, where the App Clip left the invitation.
        let clipInvite = ClipInviteHandOff(bundle: .main)?.take()
        
        guard let currentVersion = Version(InfoPlistReader(bundle: .main).bundleShortVersionString) else {
            fatalError("The app's version number **must** use semver for migration purposes.")
        }
        
        // AGENT-PLATFORM (1.0.3): upstream's migrations compare Element X releases, not our 1.0.x (`UpstreamMigrationBaseline`).
        let previousVersion = appSettings.lastVersionLaunched.flatMap(Version.init)
        let upstreamBaseline = UpstreamMigrationBaseline(marker: appSettings.upstreamMigrationsVersion,
                                                         accountFallback: appSettings.upstreamAccountMigrationsFallback,
                                                         previousAppVersion: previousVersion,
                                                         appVersion: currentVersion)
        if let previousVersion {
            performMigrationsIfNecessary(from: previousVersion, to: currentVersion, upstreamBaseline: upstreamBaseline)
        } else {
            // The app has been deleted since the previous run. Reset everything.
            wipeUserData(includingSettings: true)
        }
        // AGENT-PLATFORM (1.0.3): the fallback and marker first; a launch that kept only `lastVersionLaunched`
        // would derive 26.10.8 from it next time, and a 1.0.1 account would skip its 26.10.x migrations.
        appSettings.upstreamAccountMigrationsFallback = upstreamBaseline.accountFallbackAfterLaunch // AGENT-PLATFORM (1.0.3)
        appSettings.upstreamMigrationsVersion = upstreamBaseline.markerAfterLaunch // AGENT-PLATFORM (1.0.3)
        appSettings.lastVersionLaunched = currentVersion.description
        
        // AGENT-PLATFORM (Brief 0086): before the start screen shows, so its invitation banner is there from the start.
        adoptClipInvite(clipInvite)
        
        setupStateMachine()
        
        observeApplicationState()
        observeUserSessionChanges()
        observeAppLockChanges()
        
        registerBackgroundAppRefresh()
        registerSearchBackfill()
        
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
            MXLog.info("Received a start request when already started")
            return
        }
        
        guard !userSessionManager.userIDs.isEmpty else {
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
        // Read before resuming the services, by which time a push tap or deep link will have made the app active.
        let animated = appMediator.appState == .active
        Task {
            await asyncHandleAppRoute(appRoute, windowType: windowType, animated: animated)
        }
    }
    
    private func asyncHandleAppRoute(_ appRoute: AppRoute, windowType: SecondaryWindowType?, animated: Bool) async {
        MXLog.info("Handling app route:  \(appRoute)")
        
        await resumeClientServices()
        
        if let windowType {
            windowManager.handleRoute(appRoute, windowType: windowType)
            return
        }
        
        var handled = false
        
        switch appRoute {
        case .inviteLink: // AGENT-PLATFORM (Brief 0083 L1b): no .accountProvisioningLink
            if let authenticationFlowCoordinator {
                authenticationFlowCoordinator.handleAppRoute(appRoute, animated: animated)
                handled = true
            }
        default:
            if let userSessionFlowCoordinator {
                userSessionFlowCoordinator.handleAppRoute(appRoute, animated: animated)
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
            // AGENT-PLATFORM (Brief 0083 L1b): no .accountProvisioningLink.
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
            case .catalogTemplate, .feedPost: // AGENT-PLATFORM: .feedPost (Brief 0082)
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
        // A new login has nothing to migrate.
        markMigrated(userSession) // AGENT-PLATFORM (1.0.3): also writes the account's upstream marker
        userSessionManager.add(userSession)
        configureActiveSession()
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
        // Only the active account's rooms can be on screen.
        if let receiverID = content.receiverID, receiverID != userSession?.clientProxy.userID {
            return true
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
              let receiverID = content.receiverID else {
            return
        }
        
        if let userSession {
            guard receiverID == userSession.clientProxy.userID else {
                // TODO: Switch to the receiver's account and open the room (element-hq/element-meta#3328).
                MXLog.info("Ignoring a notification tap for \(receiverID), it isn't the active account.")
                return
            }
        } else {
            storedAppRouteReceiverID = receiverID
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
        
        guard let roomID = content.roomID,
              let receiverID = content.receiverID else {
            return
        }
        
        guard let userSession = userSessionManager.session(for: receiverID) else {
            // Store the data so it can be sent once the receiver's session is live.
            storedInlineReply = PendingInlineReplyDetails(userID: receiverID, roomID: roomID, message: replyText)
            return
        }
        
        await processInlineReply(replyText, roomID: roomID, userSession: userSession)
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
    private func performMigrationsIfNecessary(from oldAppVersion: Version, to newVersion: Version, upstreamBaseline: UpstreamMigrationBaseline) {
        // AGENT-PLATFORM (1.0.3): the thresholds below are Element X releases; compare the one already migrated to, not our 1.0.x.
        guard upstreamBaseline.needsMigrations else { return }
        let oldVersion = upstreamBaseline.appliedRelease
        
        // Be tidy and clean up after ourselves every now and then (because Apple is lazy)
        clearTemporaryDirectories()
        
        MXLog.info("The app was upgraded from \(oldAppVersion) to \(newVersion), upstream migrations from \(oldVersion)") // AGENT-PLATFORM (1.0.3)
        
        if oldVersion < Version(1, 6, 7) {
            Tracing.deleteLogFiles(in: Tracing.legacyLogsDirectory)
            MXLog.info("Migrating to v1.6.7, log files have been wiped")
        }
        
        if oldVersion < Version(25, 7, 4) {
            Tracing.migrateLogFiles()
            MXLog.info("Migrating to version 25.07.4, log files have been moved.")
        }
        
        if oldVersion < Version(26, 10, 2) {
            MXLog.info("Migrating to version 26.10.2, moving notification sounds.")
            let soundsDirectory = URL.libraryDirectory.appending(component: "Sounds", directoryHint: .isDirectory)
            
            // Sounds are now referenced directly, the duplicate file can go.
            try? FileManager.default.removeItem(at: soundsDirectory.appending(component: "currentAlert.caf"))
            
            let oldCustomTonesLocation = soundsDirectory.appending(component: "AvailableSounds", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: oldCustomTonesLocation.path(percentEncoded: false)) {
                do {
                    try FileManager.default.moveItem(at: oldCustomTonesLocation, to: URL.customTonesDirectory)
                } catch {
                    MXLog.error("Failed moving custom notification sounds: \(error)")
                }
            }
        }
        
        // Store the old version to run additional migrations on the user session once it has been set up.
        userSessionMigrationsOldVersion = oldVersion
    }
    
    // swiftlint:disable:next cyclomatic_complexity
    private func performUserSessionMigrations(_ userSession: UserSessionProtocol) async {
        // AGENT-PLATFORM (1.0.3): per account, so one a launch ended before restoring still migrates on a later launch.
        let accountBaseline = UpstreamMigrationBaseline.Account(marker: userSession.userSettings.account.upstreamMigrationsVersion,
                                                                fallback: appSettings.upstreamAccountMigrationsFallback)
        guard userSessionMigrationsOldVersion != nil || accountBaseline.needsMigrations,
              migratedUserIDs.insert(userSession.clientProxy.userID).inserted else {
            return
        }
        let oldVersion = accountBaseline.appliedRelease
        
        MXLog.info("Migrating user session from \(oldVersion)")
        
        // Vacuuming can outlast a background task, getting the app killed before the migrations below run.
        if appMediator.appState != .background {
            MXLog.info("Performing client store optimizations.")
            await userSession.clientProxy.optimizeStores()
            MXLog.info("Finished optimizing client stores.")
        }
        
        if oldVersion < Version(1, 6, 0) {
            MXLog.info("Migrating to v1.6.0, marking identity confirmation onboarding as ran.")
            userSession.userSettings.account.hasRunIdentityConfirmationOnboarding = true
            userSession.userSettings.app.hasRunNotificationPermissionsOnboarding = true
        }
        
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
        
        // AGENT-PLATFORM (Brief 0083 L1b): no 26.07.3 migration, hasSignedInBefore only gated Element Classic's import.
        
        if oldVersion < Version(26, 10, 1) {
            MXLog.info("Migrating to version 26.10.1, moving initial 'session specific' settings.")
            userSession.userSettings.account.migrateAppSettingsValue(\.hasRunIdentityConfirmationOnboardingKey)
            userSession.userSettings.account.migrateAppSettingsValue(\.searchBreadcrumbsKey)
        }
        
        if oldVersion < Version(26, 10, 2) {
            MXLog.info("Migrating to version 26.10.2, moving visible account settings.")
            userSession.userSettings.account.migrateAppSettingsValue(\.showAllRoomListActivityKey)
            userSession.userSettings.account.migrateRoomListActivityVisibility() // AGENT-PLATFORM: Spiral 1.0.1's enum
            userSession.userSettings.account.migrateAppSettingsValue(\.selectedNotificationToneKey)
            userSession.userSettings.account.migrateAppSettingsValue(\.sharePresenceKey)
            
            // Make sure system notification sounds are available in the new directory.
            if let selectedNotificationTone = userSession.userSettings.account.selectedNotificationTone {
                do {
                    MXLog.info("Copying the selected system notification sound.")
                    try NotificationToneManager.copySystemToneIfNeeded(selectedNotificationTone)
                } catch {
                    MXLog.error("Failed migrating the selected notification sound: \(error)")
                }
            }
        }
        
        if oldVersion < Version(26, 10, 3) {
            MXLog.info("Migrating to version 26.10.3, moving the notifications switch into the account.")
            userSession.userSettings.account.migrateAppSettingsValue(\.enableNotificationsKey)
        }
        
        if oldVersion < Version(26, 10, 4) {
            MXLog.info("Migrating to version 26.10.4, moving the seen invites into the account.")
            userSession.userSettings.account.migrateAppSettingsValue(\.seenInvitesKey)
        }
        
        userSession.userSettings.account.upstreamMigrationsVersion = accountBaseline.markerAfterMigrations // AGENT-PLATFORM (1.0.3)
    }
    
    // AGENT-PLATFORM (1.0.3): a new login starts on this code's settings. Not after a soft logout:
    // that account's settings are older, so its pending migrations still run on a later launch.
    private func markMigrated(_ userSession: UserSessionProtocol) {
        migratedUserIDs.insert(userSession.clientProxy.userID)
        userSession.userSettings.account.upstreamMigrationsVersion = UpstreamMigrationBaseline.syncedRelease.description
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
        userSessionManager.reset()
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
            
            if context.toState != .restoringSession {
                isSessionRestoredSubject.send(true)
            }
            
            switch (context.fromState, context.event, context.toState) {
            case (.initial, .startWithAuthentication, .signedOut):
                startAuthentication()
            case (.signedOut, .createdUserSession, .signedIn):
                setupUserSession(isNewLogin: true)
                restoreUserSessions()
            case (.initial, .startWithExistingSession, .restoringSession):
                restoreUserSessions()
            case (.restoringSession, .failedRestoringSession, .signedOut):
                showLoginErrorToast()
                presentSplashScreen()
            case (.restoringSession, .createdUserSession, .signedIn):
                setupUserSession(isNewLogin: false)
            case (.softLogout, .createdUserSession, .signedIn):
                setupUserSession(isNewLogin: false)
                restoreUserSessions()
                
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
    
    private func restoreUserSessions() {
        let previousRestorationTask = restorationTask
        restorationTask = Task {
            // A cancelled restoration may still be building a client, which mustn't share a store with a new one.
            await previousRestorationTask?.value
            
            await userSessionManager.restoreSessions { [weak self] userSession in
                await self?.performUserSessionMigrations(userSession)
            } didAdd: { [weak self] userSession in
                self?.showActiveSessionIfRestoring()
                self?.sendStoredInlineReply(from: userSession)
            }
            
            guard !Task.isCancelled else { return }
            // An account that was already live becomes the active one when those before it fail (e.g. after clearing the cache).
            showActiveSessionIfRestoring()
            
            if stateMachine.state == .restoringSession {
                MXLog.error("Failed to restore an existing session.")
                stateMachine.processEvent(.failedRestoringSession)
            }
        }
    }
    
    /// Shows the active session as soon as it's live, while the app is waiting for one.
    private func showActiveSessionIfRestoring() {
        guard stateMachine.state == .restoringSession, userSession != nil else { return }
        
        configureActiveSession()
        stateMachine.processEvent(.createdUserSession)
    }
    
    /// Sends a reply made from a notification before its account was live.
    private func sendStoredInlineReply(from userSession: UserSessionProtocol) {
        guard let storedInlineReply, storedInlineReply.userID == userSession.clientProxy.userID else { return }
        self.storedInlineReply = nil
        
        Task {
            await processInlineReply(storedInlineReply.message, roomID: storedInlineReply.roomID, userSession: userSession)
        }
    }
    
    private func startAuthentication() {
        let encryptionKeyProvider = EncryptionKeyProvider()
        // AGENT-PLATFORM (Brief 0083 L1b): no Element Classic app manager or account check.
        let authenticationService = AuthenticationService(userSessionManager: userSessionManager,
                                                          encryptionKeyProvider: encryptionKeyProvider,
                                                          appSettings: appSettings,
                                                          appHooks: appHooks)
        
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
        
        Task { await PendingInviteRefresh.refresh(link, resolver: inviteLinkResolver, appSettings: appSettings) } // AGENT-PLATFORM (Brief 0086)
    }
    
    // AGENT-PLATFORM (Brief 0086): the invitation the App Clip carried across the install, on a launch with no session.
    // The Clip may have saved a bare token (offline, or Install tapped before its answer) and the invitation may have
    // been used up since, so the server is asked again, as for a tapped link — on every launch with no session, not
    // only the adopting one: a first check that failed would leave a bare token, and a used-up one a live banner.
    private func adoptClipInvite(_ clipInvite: ClipInvite?) {
        let hasSession = !userSessionManager.userIDs.isEmpty
        if let pendingInvite = ClipInviteAdoption.pendingInvite(from: clipInvite, existing: appSettings.pendingInvite, hasSession: hasSession) {
            appSettings.pendingInvite = pendingInvite
        }

        if let link = ClipInviteAdoption.inviteToRecheck(appSettings.pendingInvite, hasSession: hasSession) {
            Task { await PendingInviteRefresh.refresh(link, resolver: inviteLinkResolver, appSettings: appSettings) }
        }
    }
    
    // AGENT-PLATFORM (Brief 0073): the first session after arriving by
    // invitation opens the welcome screen — who invited you and «Message
    // <name>», the DM made by this client (ADR-0082). The inviter's
    // assistant has meanwhile told them who joined (the referral notice).
    // 1.0.3 (operator 2026-11-21): the platform says whether the welcome is
    // owed (`fetchInviteWelcome`: a fresh seat of a personal link, by its own
    // clock, not yet welcomed), not the link this client carried — so an
    // invitation pasted on the web page counts and a sign-in to an account
    // registered otherwise is never greeted. Asked at every session start until
    // settled, so a failed request is retried; once shown, the platform records
    // it, so no later sign-in, second device or reinstall shows it again.
    private func offerInviteWelcome() {
        appSettings.pendingInvite = nil
        guard let userSession, let service = userSession.agentPlatformService else { return }
        let account = userSession.userSettings.account
        let ownUserID = userSession.clientProxy.userID
        weak var flowCoordinator = userSessionFlowCoordinator
        Task { [weak self] in
            await InviteWelcomeOffer.run(service: service,
                                         account: account,
                                         ownUserID: ownUserID,
                                         // A sign-out and another sign-in meanwhile must not get this account's welcome.
                                         isStillCurrent: { self?.userSession?.clientProxy.userID == ownUserID && flowCoordinator != nil },
                                         present: { inviter, onShown in
                                             flowCoordinator?.presentInviteWelcome(inviterUserID: inviter, onShown: onShown)
                                         })
        }
    }
    
    private func runPostSessionSetupTasks() async {
        guard let userSession, let userSessionFlowCoordinator else {
            fatalError("User session not setup")
        }
        
        if let storedAppRouteReceiverID, storedAppRouteReceiverID != userSession.clientProxy.userID {
            // TODO: Switch to the receiver's account and open the room (element-hq/element-meta#3328).
            MXLog.info("Dropping a notification tap for \(storedAppRouteReceiverID), it isn't the active account.")
            storedAppRoute = nil
            storedRoomsToAwait = nil
        }
        
        if let storedRoomsToAwait {
            userSession.clientProxy.roomsToAwait = storedRoomsToAwait
        }
        
        if storedAppRoute?.isAuthenticationRoute == false,
           let storedAppRoute = storedAppRoute.take() {
            userSessionFlowCoordinator.handleAppRoute(storedAppRoute, animated: false)
        }
        // After the stored route too: the welcome waits until onboarding has settled, over whatever the route opened.
        offerInviteWelcome()
    }
    
    private func startAuthenticationSoftLogout() {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        Task { [self] in
            let credentials = SoftLogoutScreenCredentials(userID: userSession.clientProxy.userID,
                                                          homeserverName: userSession.clientProxy.homeserver,
                                                          userDisplayName: userSession.clientProxy.userProfilePublisher.value.displayName ?? "",
                                                          deviceID: userSession.clientProxy.deviceID)
            
            let authenticationService = AuthenticationService(userSessionManager: userSessionManager,
                                                              encryptionKeyProvider: EncryptionKeyProvider(),
                                                              appSettings: appSettings,
                                                              appHooks: appHooks) // AGENT-PLATFORM (Brief 0083 L1b): no Classic app manager
            _ = await authenticationService.configure(for: userSession.clientProxy.homeserver, flow: .login)
            
            let parameters = SoftLogoutScreenCoordinatorParameters(authenticationService: authenticationService,
                                                                   credentials: credentials,
                                                                   keyBackupNeeded: false,
                                                                   appMediator: appMediator,
                                                                   appSettings: appSettings,
                                                                   appHooks: appHooks,
                                                                   userIndicatorController: userIndicatorController)
            let coordinator = SoftLogoutScreenCoordinator(parameters: parameters)
            softLogoutCoordinator = coordinator
            coordinator.actions
                .sink { [weak self] action in
                    guard let self else { return }
                    
                    switch action {
                    case .signedIn(let session):
                        self.migratedUserIDs.insert(session.clientProxy.userID)
                        self.userSessionManager.add(session)
                        self.configureActiveSession()
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
                                                  availableSessionsPublisher: userSessionManager.sessionsPublisher.map { $0.map(UserSessionDetails.init) },
                                                  bugReportService: bugReportService,
                                                  callKitService: callKitService,
                                                  timelineControllerFactory: TimelineControllerFactory(userSettings: userSession.userSettings),
                                                  emojiProvider: EmojiProvider(userSettings: userSession.userSettings),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  appMediator: appMediator,
                                                  analytics: analyticsService,
                                                  userIndicatorController: userIndicatorController,
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
        
        // TODO: With other accounts signed in, switch to the most recently used one instead (element-hq/element-meta#3325).
        restorationTask?.cancel()
        windowManager.closeAllSecondaryWindows()
        // AGENT-PLATFORM (Brief 0073): an invitation never outlives the
        // session it was accepted into.
        appSettings.pendingInvite = nil
        
        showLoadingIndicator()
        
        Task { await pauseClientServices(isBackgroundTask: false) }
        userSessionFlowCoordinator?.stop()
        // AGENT-PLATFORM (Brief 0067): upstream leaves its ElementCallService call here; Spiral's
        // calls are CallKit + native MatrixRTC, whose logout teardown is tracked in DEBT.md.
        
        guard !isSoft else {
            stateMachine.processEvent(.showSoftLogout)
            hideLoadingIndicator()
            return
        }
        
        Task {
            // Delete the pusher and stop the live location shares while the session can still reach the server.
            await userSession.notificationService.tearDown()
            await userSession.liveLocationService.stopAllLiveLocations()
            
            // First log out from the server
            await userSession.clientProxy.logout()
            
            // Regardless of the result, clear user data
            userSessionManager.remove(userID: userSession.clientProxy.userID)
            tearDownUserSession()
            
            // Signed in accounts that aren't live yet still count.
            if userSessionManager.userIDs.isEmpty {
                notificationManager.reset()
            }
            
            userSession.userSettings.account.reset()
            // AGENT-PLATFORM (Brief 0083 L1b): no remoteSettingsHook to reset.
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
        
        userSessionFlowCoordinator = nil
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
    
    /// Points the app-wide services at the active account's session.
    private func configureActiveSession() {
        guard let userSession else {
            fatalError("User session not setup")
        }
        
        callKitService.setClientProxy(userSession.clientProxy) // AGENT-PLATFORM (Brief 0067)
        Task {
            await resumeClientServices()
        }
    }
    
    private func configureNotificationManager() {
        notificationManager.delegate = self
        notificationManager.start()
        
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
        userSessionManager.callbacksPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] callback in
                guard let self else { return }
                switch callback {
                case .didReceiveAuthError(let userID, let isSoftLogout):
                    // Only the active account can be signed out for now.
                    guard userID == userSessionManager.activeSession?.clientProxy.userID else {
                        MXLog.error("Ignoring an auth error for \(userID), it isn't the active account.")
                        return
                    }
                    stateMachine.processEvent(.signOut(isSoft: isSoftLogout, disableAppLock: false))
                }
            }
            .store(in: &cancellables)
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
        
        restorationTask?.cancel()
        showLoadingIndicator()
        
        navigationRootCoordinator.setRootCoordinator(PlaceholderScreenCoordinator(hideBrandChrome: appSettings.hideBrandChrome))
        
        Task { await pauseClientServices(isBackgroundTask: false) }
        userSessionFlowCoordinator?.stop()
        
        // Allow for everything to deallocate properly
        Task {
            await userSessionManager.clearCaches(userID: userSession.clientProxy.userID)
            stateMachine.processEvent(.startWithExistingSession)
            hideLoadingIndicator()
        }
    }
    
    private func processInlineReply(_ replyText: String, roomID: String, userSession: UserSessionProtocol) async {
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
        
        await userSessionManager.pauseServices()
        clientProxyObserver = nil
    }
    
    private func resumeClientServices() async {
        guard let userSession else { return }
        
        analyticsService.signpost.startTransaction(.upToDateRoomList)
        
        await userSessionManager.resumeServices()
        
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
        // AGENT-PLATFORM (Brief 0083, question 359)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveMemoryWarning),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
    }
    
    @objc
    private func didReceiveMemoryWarning() {
        TimelineCaches.purge()
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
        scheduleSearchBackfill()
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
        // The accounts' counts come from their room lists (`NotificationService.attentionCount`).
        notificationManager.updateAppBadgeCount()
    }
    
    private func endActiveBackgroundTask() {
        guard let backgroundTask else {
            return
        }
        
        MXLog.info("Ending background task.")
        appMediator.endBackgroundTask(backgroundTask)
        self.backgroundTask = nil
    }
}

// MARK: Background app refresh

private extension AppCoordinator {
    func registerBackgroundAppRefresh() {
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
    
    func scheduleBackgroundAppRefresh() {
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
    
    func handleBackgroundAppRefresh(_ task: BGAppRefreshTask) async {
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
        
        await waitForSessionRestore()
        
        guard let userSession else {
            MXLog.info("Background app refresh: no user session, giving up.")
            task.setTaskCompleted(success: false)
            return
        }
        
        // Configure the background-refresh sync to carry set_presence=offline so it doesn't mark the
        // user online or idle. Note: If already online/idle then setting offline shouldn't override that.
        await userSessionManager.configurePresence(.offline, sendImmediately: false)
        
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
    
    /// When iOS relaunches a terminated app for a background task, the session needs restoring before the task can run.
    private func waitForSessionRestore() async {
        // A background launch doesn't necessarily connect a scene, which is what normally calls `start()`.
        if stateMachine.state == .initial, !userSessionManager.userIDs.isEmpty {
            start()
        }
        
        for await isSessionRestored in isSessionRestoredSubject.timeout(.seconds(5), scheduler: DispatchQueue.main).values where isSessionRestored {
            return
        }
    }
}

// MARK: Search backfill

private extension AppCoordinator {
    func registerSearchBackfill() {
        let result = BGTaskScheduler.shared.register(forTaskWithIdentifier: appSettings.searchBackfillTaskIdentifier, using: .main) { [weak self] task in
            guard let task = task as? BGProcessingTask else {
                MXLog.error("Invalid search backfill configuration")
                return
            }
            
            Task {
                await self?.handleSearchBackfill(task)
            }
        }
        
        MXLog.info("Register search backfill with result: \(result)")
    }
    
    func scheduleSearchBackfill() {
        guard let userSession, userSession.userSettings.app.globalSearchEnabled else {
            return
        }
        
        let request = BGProcessingTaskRequest(identifier: appSettings.searchBackfillTaskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = true
        
        do {
            try BGTaskScheduler.shared.submit(request)
            MXLog.info("Successfully scheduled search backfill task")
        } catch {
            MXLog.error("Failed scheduling search backfill with error: \(error)")
        }
    }
    
    func handleSearchBackfill(_ task: BGProcessingTask) async {
        MXLog.info("Started search backfill task")
        
        await waitForSessionRestore()
        
        task.expirationHandler = { @Sendable [weak self] in
            MXLog.info("Search backfill task is about to expire.")
            Task { @MainActor in self?.userSessionManager.stopSearchBackfill() }
        }
        
        userSessionManager.startSearchBackfill(strategy: .background)
        
        // TaskHandle can't be awaited, so poll until every sweep finishes or is stopped on expiry.
        while userSessionManager.isSearchBackfillRunning {
            try? await Task.sleep(for: .seconds(1))
        }
        
        MXLog.info("Marking search backfill task as complete.")
        task.setTaskCompleted(success: true)
    }
}

private struct PendingInlineReplyDetails {
    let userID: String
    let roomID: String
    let message: String
}
