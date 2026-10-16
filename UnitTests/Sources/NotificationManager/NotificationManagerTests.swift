//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import ElementX
import NotificationCenter
import Testing

@MainActor
final class NotificationManagerTests {
    var notificationManager: NotificationManager!
    private let clientProxy = ClientProxyMock(.init(userID: "@test:user.net"))
    private lazy var mockUserSession = UserSessionMock(.init(clientProxy: clientProxy))
    private var notificationCenter: UserNotificationCenterMock!
    private var authorizationStatusWasGranted = false
    private var shouldDisplayInAppNotificationReturnValue = false
    private var handleInlineReplyDelegateCalled = false
    private var notificationTappedDelegateCalled = false
    private var registerForRemoteNotificationsDelegateCalled: (() -> Void)?
    private let appSettings: AppSettings
    
    init() {
        appSettings = AppSettings.volatile()
        notificationCenter = UserNotificationCenterMock()
        notificationCenter.requestAuthorizationOptionsReturnValue = true
        notificationCenter.authorizationStatusReturnValue = .authorized
        notificationCenter.notificationSettingsClosure = { await UNUserNotificationCenter.current().notificationSettings() }
        
        notificationManager = NotificationManager(notificationCenter: notificationCenter, appSettings: appSettings)
        notificationManager.start()
        notificationManager.setUserSession(mockUserSession)
    }
    
    isolated deinit {
        notificationCenter = nil
        notificationManager = nil
    }
    
    @Test
    func whenRegistered_pusherIsCalled() async {
        _ = await notificationManager.register(with: Data())
        
        #expect(clientProxy.setPusherWithCalled)
    }
    
    @Test
    func whenRegisteredSuccess_completionSuccessIsCalled() async {
        let success = await notificationManager.register(with: Data())
        #expect(success)
    }
    
    @Test
    func whenRegisteredAndPusherThrowsError_completionFalseIsCalled() async {
        enum TestError: Error {
            case someError
        }
        
        clientProxy.setPusherWithThrowableError = TestError.someError
        let success = await notificationManager.register(with: Data())
        #expect(!success)
    }
    
    @Test
    func whenRegistered_pusherIsCalledWithCorrectValues() async throws {
        let pushkeyData = Data("1234".utf8)
        _ = await notificationManager.register(with: pushkeyData)
        
        guard let configuration = clientProxy.setPusherWithReceivedInvocations.first else {
            Issue.record("Invalid pusher configuration sent")
            return
        }
        
        #expect(configuration.identifiers.pushkey == pushkeyData.base64EncodedString())
        #expect(configuration.identifiers.appId == appSettings.pusherAppID)
        #expect(configuration.appDisplayName == "\(InfoPlistReader.main.bundleDisplayName) (iOS)")
        #expect(configuration.deviceDisplayName == UIDevice.current.name)
        #expect(configuration.profileTag != nil)
        #expect(configuration.lang == Bundle.app.preferredLocalizations.first)
        guard case let .http(data) = configuration.kind else {
            Issue.record("Http kind expected")
            return
        }
        #expect(data.url == appSettings.pushGatewayNotifyEndpoint.absoluteString)
        #expect(data.format == .eventIdOnly)
        let defaultPayload = APNSPayload(aps: APSInfo(mutableContent: 1,
                                                      alert: APSAlert(locKey: "Notification",
                                                                      locArgs: [])),
                                         pusherNotificationClientIdentifier: nil)
        #expect(try data.defaultPayload == (defaultPayload.toJsonString()))
    }
    
    @Test
    func whenRegisteredAndPusherTagNotSetInSettings_tagGeneratedAndSavedInSettings() async {
        appSettings.pusherProfileTag = nil
        _ = await notificationManager.register(with: Data())
        #expect(appSettings.pusherProfileTag != nil)
    }
    
    @Test
    func whenRegisteredAndPusherTagIsSetInSettings_tagNotGenerated() async {
        appSettings.pusherProfileTag = "12345"
        _ = await notificationManager.register(with: Data())
        #expect(appSettings.pusherProfileTag == "12345")
    }
    
    @Test
    func whenShowLocalNotification_notificationRequestGetsAdded() async throws {
        await notificationManager.showLocalNotification(with: "Title", subtitle: "Subtitle")
        let request = try #require(notificationCenter.addReceivedRequest)
        #expect(request.content.title == "Title")
        #expect(request.content.subtitle == "Subtitle")
    }
    
    @Test
    func whenStart_notificationCategoriesAreSet() {
        // AGENT-PLATFORM: assert by identifier set, not by full struct
        // equality — the OS routes notification taps by
        // `categoryIdentifier`, not by the full struct.
        let identifiers = notificationCenter.setNotificationCategoriesReceivedCategories?
            .map(\.identifier)
            .sorted() ?? []
        #expect(identifiers == [
            NotificationConstants.Category.approval,
            // AGENT-PLATFORM: verification joined in S157.a; the list is the
            // canonical registration contract, so every category counts.
            NotificationConstants.Category.verification,
            // Operator question 88: a block request is tap-only.
            NotificationConstants.Category.blockRequest,
            NotificationConstants.Category.invite,
            NotificationConstants.Category.message
        ].sorted())
        let blockRequest = notificationCenter.setNotificationCategoriesReceivedCategories?
            .first { $0.identifier == NotificationConstants.Category.blockRequest }
        #expect(blockRequest?.actions.isEmpty == true, "no Approve or Reject on the lock screen")
    }
    
    @Test
    func whenStart_delegateIsSet() throws {
        let delegate = try #require(notificationCenter.delegate)
        #expect(delegate.isEqual(notificationManager))
    }
    
    @Test
    func whenStart_requestAuthorizationCalledWithCorrectParams() async {
        await waitForConfirmation("requestAuthorization should be called", timeout: .seconds(10)) { confirm in
            notificationCenter.requestAuthorizationOptionsClosure = { _ in
                confirm()
                return true
            }
            notificationManager.requestAuthorization()
        }
        #expect(notificationCenter.requestAuthorizationOptionsReceivedOptions == [.alert, .sound, .badge])
    }
    
    @Test
    func whenStartAndAuthorizationGranted_delegateCalled() async {
        authorizationStatusWasGranted = false
        notificationManager.delegate = self
        await waitForConfirmation("registerForRemoteNotifications delegate function should be called", timeout: .seconds(10)) { confirm in
            registerForRemoteNotificationsDelegateCalled = {
                confirm()
            }
            notificationManager.requestAuthorization()
        }
        #expect(authorizationStatusWasGranted)
    }
    
    @Test
    func whenStartAndAuthorizedAndNotificationDisabled_registerForRemoteNotificationsNotCalled() async throws {
        appSettings.enableNotifications = false
        notificationCenter.authorizationStatusReturnValue = .authorized
        notificationManager.delegate = self
        
        notificationManager.setUserSession(UserSessionMock(.init()))
        try await Task.sleep(for: .seconds(1))
        
        #expect(!authorizationStatusWasGranted)
    }
    
    @Test
    func whenStartAndAuthorized_registerForRemoteNotificationsCalled() async {
        appSettings.enableNotifications = true
        notificationCenter.authorizationStatusReturnValue = .authorized
        notificationManager.delegate = self
        
        await waitForConfirmation("registerForRemoteNotifications delegate function should be called", timeout: .seconds(10)) { confirm in
            registerForRemoteNotificationsDelegateCalled = {
                confirm()
            }
            notificationManager.setUserSession(UserSessionMock(.init()))
        }
        
        #expect(authorizationStatusWasGranted)
    }
    
    @Test
    func whenWillPresentNotificationsDelegateNotSet_CorrectPresentationOptionsReturned() async throws {
        let archiver = MockCoder(requiringSecureCoding: false)
        let notification = try #require(UNNotification(coder: archiver))
        let options = await notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: notification)
        #expect(options == [.badge, .sound, .list, .banner])
    }
    
    @Test
    func whenWillPresentNotificationsDelegateSetAndNotificationsShoudNotBeDisplayed_CorrectPresentationOptionsReturned() async throws {
        shouldDisplayInAppNotificationReturnValue = false
        notificationManager.delegate = self
        
        let notification = try UNNotification.with(userInfo: [AnyHashable: Any]())
        let options = await notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: notification)
        #expect(options == [])
    }
    
    @Test
    func whenWillPresentNotificationsDelegateSetAndNotificationsShoudBeDisplayed_CorrectPresentationOptionsReturned() async throws {
        shouldDisplayInAppNotificationReturnValue = true
        notificationManager.delegate = self
        
        let notification = try UNNotification.with(userInfo: [AnyHashable: Any]())
        let options = await notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), willPresent: notification)
        #expect(options == [.badge, .sound, .list, .banner])
    }
    
    @Test
    func whenNotificationCenterReceivedResponseInLineReply_delegateIsCalled() async throws {
        handleInlineReplyDelegateCalled = false
        notificationManager.delegate = self
        let response = try UNTextInputNotificationResponse.with(userInfo: [AnyHashable: Any](), actionIdentifier: NotificationConstants.Action.inlineReply)
        await notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: response)
        #expect(handleInlineReplyDelegateCalled)
    }
    
    @Test
    func whenNotificationCenterReceivedResponseWithActionIdentifier_delegateIsCalled() async throws {
        notificationTappedDelegateCalled = false
        notificationManager.delegate = self
        let response = try UNTextInputNotificationResponse.with(userInfo: [AnyHashable: Any](), actionIdentifier: UNNotificationDefaultActionIdentifier)
        await notificationManager.userNotificationCenter(UNUserNotificationCenter.current(), didReceive: response)
        #expect(notificationTappedDelegateCalled)
    }

    // MARK: - App icon badge (AGENT-PLATFORM)

    /// The badge counts ROOMS needing attention — the number upstream's own
    /// issue tracker says it should be (element-x-ios#2066: "the number of
    /// rooms with unread push notifs") and the MSC4076 model: the E2EE
    /// client computes it, because the server cannot see inside encryption.
    @Test
    func badgeCountsRoomsNeedingAttentionNotMessages() async {
        appSettings.roomListActivityVisibility = .current
        let rooms: [RoomSummary] = [
            .mock(id: "!a:hs", name: "A", unreadMessagesCount: 7),
            .mock(id: "!b:hs", name: "B", isMarkedUnread: true),
            .mock(id: "!c:hs", name: "C")
        ]

        await notificationManager.updateBadgeCount(with: rooms)

        #expect(notificationCenter.setBadgeCountReceivedCount == 2,
                "two rooms ask for attention — seven messages in one room are still ONE room")
    }

    /// The badge obeys the same visibility setting as the dots: in the
    /// mode that hides plain unreads, a room with only unread messages
    /// (no notifying events) must not be counted — otherwise the icon
    /// nags about a room the list shows as clean.
    @Test
    func badgeFollowsTheRoomListVisibilitySetting() async {
        let rooms: [RoomSummary] = [
            .mock(id: "!plain:hs", name: "Plain unreads", unreadMessagesCount: 3),
            .mock(id: "!notifying:hs", name: "Notifying", unreadNotificationsCount: 1)
        ]

        appSettings.roomListActivityVisibility = .current
        await notificationManager.updateBadgeCount(with: rooms)
        #expect(notificationCenter.setBadgeCountReceivedCount == 2)

        appSettings.roomListActivityVisibility = .hide
        await notificationManager.updateBadgeCount(with: rooms)
        #expect(notificationCenter.setBadgeCountReceivedCount == 1,
                "a room the list renders clean must not keep a badge on the icon")
    }

    /// Everything read → zero. This is the reported bug: the badge said 2
    /// while nothing was unread, because nothing ever recomputed it.
    @Test
    func badgeClearsWhenEverythingIsRead() async {
        appSettings.roomListActivityVisibility = .current
        await notificationManager.updateBadgeCount(with: [
            .mock(id: "!a:hs", name: "A"),
            .mock(id: "!b:hs", name: "B")
        ])

        #expect(notificationCenter.setBadgeCountReceivedCount == 0)
    }

    /// A muted room with notifying events stays OFF the badge in the
    /// modes that respect mutes — muting a noisy room is precisely the
    /// user saying "stop counting this at me".
    @Test
    func badgeRespectsMutes() async {
        appSettings.roomListActivityVisibility = .hide
        let rooms: [RoomSummary] = [
            .mock(id: "!muted:hs", name: "Muted", unreadNotificationsCount: 5, notificationMode: .mute)
        ]

        await notificationManager.updateBadgeCount(with: rooms)

        #expect(notificationCenter.setBadgeCountReceivedCount == 0)
    }
}

extension NotificationManagerTests: @MainActor NotificationManagerDelegate {
    func registerForRemoteNotifications() {
        authorizationStatusWasGranted = true
        registerForRemoteNotificationsDelegateCalled?()
    }
    
    func unregisterForRemoteNotifications() {
        authorizationStatusWasGranted = false
    }
    
    func shouldDisplayInAppNotification(content: UNNotificationContent) -> Bool {
        shouldDisplayInAppNotificationReturnValue
    }
    
    func notificationTapped(content: UNNotificationContent) async {
        notificationTappedDelegateCalled = true
    }
    
    func handleInlineReply(_ service: ElementX.NotificationManagerProtocol, content: UNNotificationContent, replyText: String) async {
        handleInlineReplyDelegateCalled = true
    }

    // AGENT-PLATFORM: protocol conformance stub for the new
    // approval-action delegate method. Not exercised by existing
    // tests; covered separately in ApprovalActionRunnerTests.
    func handleApprovalAction(_ service: NotificationManagerProtocol,
                              content: UNNotificationContent,
                              decision: ApprovalDecision) async { }
}
