//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 187): the Settings rework — Blocked users in
// Privacy, Appearance & media.
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct PrivacySettingsTests {
    @Test
    func blockedUsersShowsOnlyWhileSomeoneIsBlocked() async throws {
        let ignoredUsers = CurrentValueSubject<[String]?, Never>(["@bob:example.com"])
        let viewModel = makeViewModel(ignoredUsers: ignoredUsers)
        
        let shown = deferFulfillment(viewModel.context.observe(\.viewState.showBlockedUsers)) { $0 }
        try await shown.fulfill()
        
        let hidden = deferFulfillment(viewModel.context.observe(\.viewState.showBlockedUsers)) { !$0 }
        ignoredUsers.send([])
        try await hidden.fulfill()
    }
    
    @Test
    func blockedUsersRowOpensTheList() async throws {
        let viewModel = makeViewModel(ignoredUsers: .init(["@bob:example.com"]))
        
        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            switch action {
            case .blockedUsers: true
            }
        }
        viewModel.context.send(viewAction: .blockedUsers)
        try await deferred.fulfill()
    }
    
    private func makeViewModel(ignoredUsers: CurrentValueSubject<[String]?, Never>) -> ModerationAndSafetySettingsScreenViewModel {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.ignoredUsersPublisher = ignoredUsers.asCurrentValuePublisher()
        return ModerationAndSafetySettingsScreenViewModel(userSession: UserSessionMock(.init(clientProxy: clientProxy)),
                                                          userIndicatorController: UserIndicatorControllerMock())
    }
}

@MainActor
struct AppearanceAndMediaSettingsScreenViewModelTests {
    @Test
    func optimiseMediaIsTracked() {
        let appSettings = AppSettings.volatile()
        let analytics = AnalyticsServiceMock(.init())
        let viewModel = AppearanceAndMediaSettingsScreenViewModel(settings: appSettings, analytics: analytics)
        
        appSettings.optimizeMediaUploads = false
        viewModel.context.send(viewAction: .optimizeMediaUploadsChanged)
        
        #expect(analytics.trackInteractionIndexNameReceivedArguments?.name == .MobileSettingsOptimizeMediaUploadsDisabled)
    }
}
