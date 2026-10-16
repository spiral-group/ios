//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0078): deleting a Spiral account from Element X's
// Delete account screen — Face ID / the passcode (or, with no passcode, the
// typed handle), then `DELETE /me`.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct SpiralAccountDeletionTests {
    let service = AgentPlatformServiceMock()
    let authenticator = DeviceOwnerAuthenticatorMock()
    let viewModel: DeactivateAccountScreenViewModel

    var context: DeactivateAccountScreenViewModelType.Context {
        viewModel.context
    }

    init() {
        authenticator.authenticateReasonReturnValue = .authenticated
        service.deleteAccountReturnValue = .success(())
        viewModel = DeactivateAccountScreenViewModel(clientProxy: ClientProxyMock(.init(userID: "@alice:spiral.md")),
                                                     userIndicatorController: UserIndicatorControllerMock(),
                                                     spiralDeletion: .init(agentPlatformService: service,
                                                                           authenticator: authenticator))
    }

    /// Taps «Delete account» and returns the confirmation's «Delete» action.
    private func confirmationAction() async throws -> () -> Void {
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        context.send(viewAction: .deactivate)
        try await deferred.fulfill()
        return try #require(context.alertInfo?.primaryButton.action)
    }

    @Test
    func screenAsksForNoPasswordAndListsTheAssistant() {
        #expect(context.viewState.isSpiralAccount)
        #expect(context.viewState.infoPointAssistant != nil)
    }

    @Test
    func confirmedDeletionDeletesTheAccountAndLogsOut() async throws {
        let confirm = try await confirmationAction()
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .accountDeactivated }
        confirm()
        try await deferred.fulfill()

        #expect(authenticator.authenticateReasonCallsCount == 1)
        #expect(service.deleteAccountCallsCount == 1)
    }

    @Test
    func accountAlreadyGoneStillLogsOut() async throws {
        service.deleteAccountReturnValue = .failure(.notFound)
        let confirm = try await confirmationAction()
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .accountDeactivated }
        confirm()
        try await deferred.fulfill()
    }

    @Test
    func failedDeletionShowsAlertAndStaysSignedIn() async throws {
        service.deleteAccountReturnValue = .failure(.serverError(status: 503))
        let confirm = try await confirmationAction()
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .deactivationFailed }
        let noLogout = deferFailure(viewModel.actionsPublisher, timeout: .seconds(1)) { $0 == .accountDeactivated }
        confirm()
        try await deferred.fulfill()
        try await noLogout.fulfill()

        #expect(context.alertInfo?.message == UntranslatedL10n.screenDeactivateAccountSpiralFailed)
    }

    @Test
    func cancelledFaceIDDeletesNothing() async throws {
        authenticator.authenticateReasonReturnValue = .cancelled
        let confirm = try await confirmationAction()
        let noLogout = deferFailure(viewModel.actionsPublisher, timeout: .seconds(1)) { $0 == .accountDeactivated }
        confirm()
        try await noLogout.fulfill()

        #expect(service.deleteAccountCallsCount == 0)
    }

    /// Decision 112: a phone with no passcode has no owner check, so the
    /// account's handle, typed out, confirms the deletion instead.
    @Test(arguments: ["alice", "@alice", " @Alice:spiral.md "])
    func noPasscodeDeletesOnceTheHandleIsTyped(typed: String) async throws {
        authenticator.authenticateReasonReturnValue = .passcodeRequired
        let alert = try await handleConfirmation()
        #expect(alert.message == UntranslatedL10n.screenDeactivateAccountSpiralHandlePrompt("@alice"))

        let field = try #require(alert.textFields?.first)
        field.text.wrappedValue = typed
        let delete = try #require(alert.secondaryButton?.action)
        let deferred = deferFulfillment(viewModel.actionsPublisher) { $0 == .accountDeactivated }
        delete()
        try await deferred.fulfill()

        #expect(service.deleteAccountCallsCount == 1)
    }

    @Test(arguments: ["bob", "", "@alice:other.org"])
    func noPasscodeAndAWrongHandleDeletesNothing(typed: String) async throws {
        authenticator.authenticateReasonReturnValue = .passcodeRequired
        let alert = try await handleConfirmation()

        let field = try #require(alert.textFields?.first)
        field.text.wrappedValue = typed
        let delete = try #require(alert.secondaryButton?.action)
        delete()

        #expect(context.alertInfo?.id == .deactivationFailed)
        #expect(context.alertInfo?.message == UntranslatedL10n.screenDeactivateAccountSpiralHandleMismatch)
        #expect(service.deleteAccountCallsCount == 0)
    }

    /// Confirms the deletion on a phone without a passcode and returns the
    /// alert that asks for the handle.
    private func handleConfirmation() async throws -> AlertInfo<DeactivateAccountScreenAlert> {
        let confirm = try await confirmationAction()
        let deferred = deferFulfillment(context.observe(\.viewState.bindings.alertInfo)) { $0?.id == .handleConfirmation }
        confirm()
        return try #require(try await deferred.fulfill())
    }
}
