//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct SettingsScreenViewModelTests {
    private var clientProxy: ClientProxyMock!
    private var viewModel: SettingsScreenViewModelProtocol!
    private var context: SettingsScreenViewModelType.Context {
        viewModel.context
    }
    
    // MARK: - User status
    
    @Test
    mutating func statusPickerFlow() {
        // Given a screen where no status has been set.
        setupViewModel()
        #expect(!context.viewState.bindings.isPresentingStatusPicker)
        #expect(!context.viewState.bindings.isShowingCustomStatusField)
        #expect(context.viewState.userStatusRowMode == .pickStatusButton)
        
        // When choosing to pick a status.
        context.send(viewAction: .userStatus(.pickStatus))
        
        // Then the status picker should be presented.
        #expect(context.viewState.bindings.isPresentingStatusPicker)
        #expect(!context.viewState.bindings.isShowingCustomStatusField)
        #expect(context.viewState.userStatusRowMode == .pickStatusButton)
        
        // When choosing to enter a custom status.
        context.send(viewAction: .userStatus(.customStatus))
        
        // Then the picker should be dismissed and the custom status field shown.
        #expect(!context.viewState.bindings.isPresentingStatusPicker)
        #expect(context.viewState.bindings.isShowingCustomStatusField)
        #expect(context.viewState.userStatusRowMode == .customStatusInput(emoji: "😄"))
        
        // When cancelling.
        context.send(viewAction: .userStatus(.cancel))
        
        // Then all status editing should be dismissed.
        #expect(!context.viewState.bindings.isPresentingStatusPicker)
        #expect(!context.viewState.bindings.isShowingCustomStatusField)
        #expect(context.viewState.userStatusRowMode == .pickStatusButton)
    }
    
    @Test
    mutating func persistingStatus() async throws {
        // Given a screen where no status has been set or removed yet.
        setupViewModel()
        #expect(clientProxy.setUserStatusCallsCount == 0)
        #expect(clientProxy.clearUserStatusCallsCount == 0)
        
        // When setting a status.
        let status = UserStatus.Raw(text: "Away", emoji: "🌴")
        let (setStream, setContinuation) = AsyncStream<UserStatus.Raw>.makeStream()
        clientProxy.setUserStatusClosure = {
            setContinuation.yield($0)
            return .success(())
        }
        let statusSet = deferFulfillment(setStream) { _ in true }
        context.send(viewAction: .userStatus(.set(status)))
        
        // Then only the set endpoint should be called, with the chosen status.
        #expect(try await statusSet.fulfill() == status)
        #expect(clientProxy.setUserStatusCallsCount == 1)
        #expect(clientProxy.clearUserStatusCallsCount == 0)
        
        // When clearing the status.
        let (removeStream, removeContinuation) = AsyncStream<Void>.makeStream()
        clientProxy.clearUserStatusClosure = {
            removeContinuation.yield()
            return .success(())
        }
        let statusRemoved = deferFulfillment(removeStream) { _ in true }
        context.send(viewAction: .userStatus(.clear))
        
        // Then the clear user status endpoint should be called.
        try await statusRemoved.fulfill()
        #expect(clientProxy.clearUserStatusCallsCount == 1)
        #expect(clientProxy.setUserStatusCallsCount == 1)
    }
    
    @Test
    mutating func clearCallStatus() async throws {
        // Given a screen where the user has a call status set.
        let callStatus = UserStatus.mockCall
        setupViewModel(status: callStatus)
        #expect(!clientProxy.clearUserStatusCalled)
        #expect(!clientProxy.setUserStatusCalled)
        
        // When clearing the status.
        let (removeStream, removeContinuation) = AsyncStream<Void>.makeStream()
        clientProxy.clearUserStatusClosure = {
            removeContinuation.yield()
            return .success(())
        }
        let statusRemoved = deferFulfillment(removeStream) { _ in true }
        context.send(viewAction: .userStatus(.clear))
        
        // Then the clear user status endpoint should be called.
        try await statusRemoved.fulfill()
        #expect(clientProxy.clearUserStatusCallsCount == 1)
        #expect(!clientProxy.setUserStatusCalled)
    }
    
    @Test
    mutating func showsExistingStatus() throws {
        // Given a screen where the user has a status set.
        let status = UserStatus.mockHoliday
        setupViewModel(status: status)
        
        // Then that status should be shown.
        let displayedStatus = try #require(status.displayed)
        #expect(context.viewState.userStatusRowMode == .showingStatus(displayedStatus))
    }
    
    @Test
    mutating func selectingCustomStatusEmoji() async throws {
        // Given a custom status field showing the default emoji.
        setupViewModel()
        context.send(viewAction: .userStatus(.customStatus))
        #expect(context.viewState.userStatusRowMode == .customStatusInput(emoji: "😄"))
        
        // When selecting an emoji from the picker.
        try await selectCustomStatusEmoji("🎉")
        
        // Then the custom status field should show the selected emoji.
        #expect(context.viewState.userStatusRowMode == .customStatusInput(emoji: "🎉"))
        
        // When cancelling and returning to the custom status field.
        context.send(viewAction: .userStatus(.cancel))
        context.send(viewAction: .userStatus(.customStatus))
        
        // Then the emoji should have been reset to the default.
        #expect(context.viewState.userStatusRowMode == .customStatusInput(emoji: "😄"))
    }
    
    @Test
    mutating func reportBug() async throws {
        setupViewModel()
        
        let deferred = deferFulfillment(viewModel.actions) { $0.isReportBug }
        context.send(viewAction: .reportBug)
        try await deferred.fulfill()
    }
    
    @Test
    mutating func analytics() async throws {
        setupViewModel()
        
        let deferred = deferFulfillment(viewModel.actions) { $0.isAnalytics }
        context.send(viewAction: .analytics)
        try await deferred.fulfill()
    }
    
    // AGENT-PLATFORM (decision 187): Encryption moved into the Security hub;
    // Element's recovery nudge stays visible on the hub's row.
    @Test
    mutating func securityRowCarriesTheRecoveryBadge() async throws {
        setupViewModel(securityState: .init(verificationState: .verified, recoveryState: .disabled))
        let badged = deferFulfillment(context.observe(\.viewState.showSecuritySectionBadge)) { $0 }
        try await badged.fulfill()
        
        setupViewModel(securityState: .init(verificationState: .verified, recoveryState: .enabled))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!context.viewState.showSecuritySectionBadge)
    }
    
    // AGENT-PLATFORM (decision 187).
    @Test
    mutating func hubRowsOpenTheirScreens() async throws {
        setupViewModel()
        
        let security = deferFulfillment(viewModel.actions) { $0.isSecurity }
        context.send(viewAction: .security)
        try await security.fulfill()
        
        let privacy = deferFulfillment(viewModel.actions) { $0.isPrivacy }
        context.send(viewAction: .privacy)
        try await privacy.fulfill()
        
        let appearance = deferFulfillment(viewModel.actions) { $0.isAppearanceAndMedia }
        context.send(viewAction: .appearanceAndMedia)
        try await appearance.fulfill()
    }
    
    @Test
    mutating func logout() async throws {
        setupViewModel()
        
        let deferred = deferFulfillment(viewModel.actions) { $0.isLogout }
        context.send(viewAction: .logout)
        try await deferred.fulfill()
    }
    
    // AGENT-PLATFORM (decision 187): no add account row — Spiral's Settings keeps its own menu.
    
    // MARK: - Helpers
    
    private mutating func setupViewModel(status: UserStatus = .init(),
                                         userSettings: UserSettings = .mock(),
                                         securityState: SessionSecurityState = .init(verificationState: .verified, recoveryState: .enabled)) {
        clientProxy = ClientProxyMock(.init(userID: "", status: status))
        let userSession = UserSessionMock(.init(clientProxy: clientProxy, userSettings: userSettings))
        userSession.sessionSecurityStatePublisher = CurrentValueSubject(securityState).asCurrentValuePublisher()
        viewModel = SettingsScreenViewModel(userSession: userSession,
                                            isBugReportServiceEnabled: true,
                                            isInSecondaryWindow: false,
                                            userIndicatorController: UserIndicatorControllerMock())
    }
    
    /// Shows the emoji picker and selects the provided emoji through its continuation.
    private func selectCustomStatusEmoji(_ emoji: String) async throws {
        let pickerPresented = deferFulfillment(viewModel.actions) { $0.isUserStatusEmojiPicker }
        context.send(viewAction: .userStatus(.pickCustomEmoji))
        guard case let .userStatusEmojiPicker(continuation) = try await pickerPresented.fulfill() else {
            Issue.record("Expected the emoji picker to be presented.")
            return
        }
        
        let emojiUpdated = deferFulfillment(context.observe(\.viewState.bindings.customStatusEmoji)) { $0 == Character(emoji) }
        continuation.yield(emoji)
        try await emojiUpdated.fulfill()
    }
}

private extension SettingsScreenViewModelAction {
    var isUserStatusEmojiPicker: Bool {
        switch self {
        case .userStatusEmojiPicker: true
        default: false
        }
    }
    
    var isReportBug: Bool {
        switch self {
        case .reportBug: true
        default: false
        }
    }
    
    var isAnalytics: Bool {
        switch self {
        case .analytics: true
        default: false
        }
    }
    
    var isLogout: Bool {
        switch self {
        case .logout: true
        default: false
        }
    }
    
    var isSecurity: Bool {
        switch self {
        case .security: true
        default: false
        }
    }
    
    var isPrivacy: Bool {
        switch self {
        case .privacy: true
        default: false
        }
    }
    
    var isAppearanceAndMedia: Bool {
        switch self {
        case .appearanceAndMedia: true
        default: false
        }
    }
}
