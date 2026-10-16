//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Testing

@MainActor
struct DeclineAndBlockScreenViewModelTests {
    var viewModel: DeclineAndBlockScreenViewModelProtocol
    var clientProxy: ClientProxyMock
    
    var context: DeclineAndBlockScreenViewModelType.Context {
        viewModel.context
    }
    
    init() {
        clientProxy = ClientProxyMock(.init())
        viewModel = DeclineAndBlockScreenViewModel(userID: "@alice:matrix.org",
                                                   roomID: "!room:matrix.org",
                                                   clientProxy: clientProxy,
                                                   userIndicatorController: UserIndicatorControllerMock())
    }
    
    @Test
    func initialState() {
        #expect(!context.viewState.isDeclineDisabled)
        #expect(!context.shouldReport)
        #expect(context.shouldBlockUser)
    }
    
    @Test
    mutating func declineDisabled() {
        context.shouldBlockUser = false
        #expect(context.viewState.isDeclineDisabled)
        #expect(!context.shouldReport)
        #expect(!context.shouldBlockUser)
        context.shouldReport = true
        // Should report set to `true` always requires a non empty reason
        #expect(context.viewState.isDeclineDisabled)
        context.reportReason = "Test reason"
        #expect(!context.viewState.isDeclineDisabled)
    }
    
    @Test
    mutating func declineBlockAndReport() async throws {
        let reason = "Test reason"
        clientProxy.roomForIdentifierClosure = { id in
            #expect(id == "!room:matrix.org")
            let roomProxyMock = InvitedRoomProxyMock(.init(id: id))
            roomProxyMock.rejectInvitationReturnValue = .success(())
            return .invited(InvitedRoomProxyMock(.init(id: id)))
        }
        clientProxy.reportRoomForIdentifierReasonClosure = { id, reasonValue in
            #expect(id == "!room:matrix.org")
            #expect(reasonValue == reason)
            return .success(())
        }
        clientProxy.ignoreUserClosure = { userId in
            #expect(userId == "@alice:matrix.org")
            return .success(())
        }
        
        context.shouldReport = true
        context.reportReason = reason
        
        let deferredAction = deferFulfillment(viewModel.actionsPublisher) { action in
            action == .dismiss(hasDeclined: true)
        }
        context.send(viewAction: .decline)
        try await deferredAction.fulfill()
        #expect(clientProxy.roomForIdentifierCalled)
        #expect(clientProxy.reportRoomForIdentifierReasonCalled)
        #expect(clientProxy.ignoreUserCalled)
    }
    
    // AGENT-PLATFORM (re-walk review): the block's result overwrote the
    // report's, so a report that failed ended in «Success».
    @Test(arguments: [(reportFails: true, blockFails: false),
                      (reportFails: false, blockFails: true),
                      (reportFails: false, blockFails: false)])
    mutating func declineReportAndBlockSaysWhetherBothWorked(reportFails: Bool, blockFails: Bool) async throws {
        let indicators = UserIndicatorControllerMock()
        var titles: [String] = []
        indicators.submitIndicatorDelayClosure = { indicator, _ in titles.append(indicator.title) }
        viewModel = DeclineAndBlockScreenViewModel(userID: "@alice:matrix.org",
                                                   roomID: "!room:matrix.org",
                                                   clientProxy: clientProxy,
                                                   userIndicatorController: indicators)
        clientProxy.roomForIdentifierClosure = { id in .invited(InvitedRoomProxyMock(.init(id: id))) }
        clientProxy.reportRoomForIdentifierReasonReturnValue = reportFails ? .failure(.sdkError(ClientProxyMockError.generic)) : .success(())
        clientProxy.ignoreUserReturnValue = blockFails ? .failure(.sdkError(ClientProxyMockError.generic)) : .success(())
        context.shouldReport = true
        context.reportReason = "Spam"
        
        let deferredAction = deferFulfillment(viewModel.actionsPublisher) { $0 == .dismiss(hasDeclined: true) }
        context.send(viewAction: .decline)
        try await deferredAction.fulfill()
        
        let expected = reportFails || blockFails ? L10n.errorUnknown : L10n.commonSuccess
        #expect(titles.last == expected)
    }
}
