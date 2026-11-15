//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.

import Foundation
@testable import Spiral
import Testing

@MainActor
struct VerificationDetailScreenViewModelTests {
    // MARK: - State derivation (pure mapping)

    @Test
    func derive_pendingDhExchangeMapsToWaitingForEmojis() {
        let result = VerificationDetailScreenViewModel.derive(state: Self.detailWith(state: .pendingDhExchange,
                                                                                     emojis: nil))
        #expect(result == .waitingForEmojis)
    }

    @Test
    func derive_pendingOwnerWithSevenEmojisMapsToReadyForReview() {
        let result = VerificationDetailScreenViewModel.derive(state: Self.detailWith(state: .pendingOwner,
                                                                                     emojis: Self.sevenEmojis))
        if case .readyForReview(let emojis) = result {
            #expect(emojis.count == 7)
        } else {
            Issue.record("Expected .readyForReview, got \(result)")
        }
    }

    @Test
    func derive_pendingOwnerWithNilEmojisFallsBackToWaiting() {
        let result = VerificationDetailScreenViewModel.derive(state: Self.detailWith(state: .pendingOwner,
                                                                                     emojis: nil))
        #expect(result == .waitingForEmojis)
    }

    @Test
    func derive_pendingOwnerWithWrongCountFallsBackToWaiting() {
        let result = VerificationDetailScreenViewModel.derive(state: Self.detailWith(state: .pendingOwner,
                                                                                     emojis: Array(Self.sevenEmojis.prefix(3))))
        #expect(result == .waitingForEmojis)
    }

    @Test
    func derive_awaitingRemoteDoneMaps() {
        let result = VerificationDetailScreenViewModel.derive(state: Self.detailWith(state: .awaitingRemoteDone,
                                                                                     emojis: nil))
        #expect(result == .awaitingRemoteDone)
    }

    @Test
    func derive_cancelledCarriesCancelCode() {
        let result = VerificationDetailScreenViewModel.derive(state: Self.detailWith(state: .cancelled,
                                                                                     emojis: nil,
                                                                                     cancelCode: "m.mac"))
        if case .cancelled(let reason) = result {
            #expect(reason == "m.mac")
        } else {
            Issue.record("Expected .cancelled, got \(result)")
        }
    }

    @Test
    func derive_unknownStateMapsToFailed() {
        let result = VerificationDetailScreenViewModel.derive(state: Self.detailWith(state: .unknown(rawValue: "future"),
                                                                                     emojis: nil))
        if case .failed(let reason) = result {
            #expect(reason.contains("future"))
        } else {
            Issue.record("Expected .failed, got \(result)")
        }
    }

    // MARK: - Behaviour

    @Test
    func appearedAction_fetchesDetailAndSeedsState() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .success(Self.detailWith(state: .pendingOwner,
                                                                          emojis: Self.sevenEmojis))

        let viewModel = VerificationDetailScreenViewModel(verificationID: "verif-1",
                                                          agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .readyForReview = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.requesterUserID == "@alice:spiral.md")
        #expect(viewModel.context.viewState.requesterDeviceID == "IPHONEDEVICE")
        #expect(viewModel.context.viewState.deadlineAt != nil)
    }

    @Test
    func fetch_404MapsToCancelledNotFailed() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .failure(.notFound)

        let viewModel = VerificationDetailScreenViewModel(verificationID: "verif-1",
                                                          agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .cancelled = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()
    }

    @Test
    func fetch_serverErrorMapsToFailedWithAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .failure(.serverError(status: 500))

        let viewModel = VerificationDetailScreenViewModel(verificationID: "verif-1",
                                                          agentPlatformService: service)

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    @Test
    func confirmAction_sendsTrueAcknowledgementAndEmitsDecided() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .success(Self.detailWith(state: .pendingOwner,
                                                                          emojis: Self.sevenEmojis))
        service.confirmVerificationIdReturnValue = .success(Self.detailWith(state: .awaitingRemoteDone,
                                                                            emojis: Self.sevenEmojis))

        let viewModel: VerificationDetailScreenViewModelProtocol =
            VerificationDetailScreenViewModel(verificationID: "verif-1",
                                              agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decided = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .confirm)
        try await deferred.fulfill()

        #expect(service.confirmVerificationIdCallsCount == 1)
    }

    @Test
    func confirmAction_409MapsToCancelledNotAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .success(Self.detailWith(state: .pendingOwner,
                                                                          emojis: Self.sevenEmojis))
        service.confirmVerificationIdReturnValue = .failure(.conflict(detail: "no longer active"))

        let viewModel = VerificationDetailScreenViewModel(verificationID: "verif-1",
                                                          agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.detailState)) {
            if case .cancelled = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .confirm)
        try await deferred.fulfill()

        // 409 should not raise an alert — cancelled state is
        // the user-visible outcome.
        #expect(viewModel.context.viewState.bindings.alertInfo == nil)
    }

    @Test
    func confirmAction_serverErrorRollsBackToReadyAndShowsAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .success(Self.detailWith(state: .pendingOwner,
                                                                          emojis: Self.sevenEmojis))
        service.confirmVerificationIdReturnValue = .failure(.serverError(status: 500))

        let viewModel = VerificationDetailScreenViewModel(verificationID: "verif-1",
                                                          agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        viewModel.context.send(viewAction: .confirm)
        try await Task.sleep(for: .milliseconds(30))

        if case .readyForReview = viewModel.context.viewState.detailState {
            // expected
        } else {
            Issue.record("Expected rollback to .readyForReview, got \(viewModel.context.viewState.detailState)")
        }
        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    @Test
    func rejectAction_emitsDecidedOnSuccess() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .success(Self.detailWith(state: .pendingOwner,
                                                                          emojis: Self.sevenEmojis))
        service.rejectVerificationIdReturnValue = .success(Self.detailWith(state: .cancelled,
                                                                           emojis: nil,
                                                                           cancelCode: "m.user"))

        let viewModel: VerificationDetailScreenViewModelProtocol =
            VerificationDetailScreenViewModel(verificationID: "verif-1",
                                              agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .decided = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .reject)
        try await deferred.fulfill()
    }

    @Test
    func doneAction_emitsDismissed() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .success(Self.detailWith(state: .confirmed,
                                                                          emojis: nil))

        let viewModel: VerificationDetailScreenViewModelProtocol =
            VerificationDetailScreenViewModel(verificationID: "verif-1",
                                              agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        let deferred = deferFulfillment(viewModel.actionsPublisher) { action in
            if case .dismissed = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .done)
        try await deferred.fulfill()
    }

    @Test
    func confirmAction_isNoOpOutsideReadyState() async throws {
        let service = AgentPlatformServiceMock()
        service.fetchVerificationIdReturnValue = .success(Self.detailWith(state: .pendingDhExchange,
                                                                          emojis: nil))

        let viewModel = VerificationDetailScreenViewModel(verificationID: "verif-1",
                                                          agentPlatformService: service)
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))

        viewModel.context.send(viewAction: .confirm)
        try await Task.sleep(for: .milliseconds(20))

        // Should never have called the network.
        #expect(service.confirmVerificationIdCallsCount == 0)
    }

    // MARK: - Fixtures

    static let sevenEmojis: [VerificationEmoji] = [
        VerificationEmoji(symbol: "🐶", description: "Dog"),
        VerificationEmoji(symbol: "🐱", description: "Cat"),
        VerificationEmoji(symbol: "🦁", description: "Lion"),
        VerificationEmoji(symbol: "🐎", description: "Horse"),
        VerificationEmoji(symbol: "🦄", description: "Unicorn"),
        VerificationEmoji(symbol: "🐷", description: "Pig"),
        VerificationEmoji(symbol: "🐘", description: "Elephant")
    ]

    static func detailWith(state: AgentVerificationState,
                           emojis: [VerificationEmoji]?,
                           cancelCode: String? = nil) -> VerificationDetail {
        VerificationDetail(id: "verif-1",
                           agentID: "agent-1",
                           ownerUserID: "@owner:spiral.md",
                           requesterUserID: "@alice:spiral.md",
                           requesterDeviceID: "IPHONEDEVICE",
                           state: state,
                           emojis: emojis,
                           cancelCode: cancelCode,
                           createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                           deadlineAt: Date(timeIntervalSince1970: 1_700_000_300),
                           decidedAt: nil,
                           decidedBy: nil)
    }
}
