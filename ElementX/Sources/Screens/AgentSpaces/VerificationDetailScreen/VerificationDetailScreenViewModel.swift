//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModel.swift`.

import Combine
import SwiftUI

typealias VerificationDetailScreenViewModelType = StateStoreViewModelV2<VerificationDetailScreenViewState, VerificationDetailScreenViewAction>

/// Drives `VerificationDetailScreen`. Fetches the verification
/// approval on `.appeared`, lets the user confirm or reject via
/// the two decision buttons, surfaces wire / state errors
/// inline.
///
/// ### Strict-SAS UX
///
/// Upstream Element X presents two buttons ("They match" /
/// "They don't match") with a warning header instructing the
/// user to compare emojis out-of-band first. We adopt the same
/// pattern, so there is **no separate checkbox**: the act of
/// tapping "They match" IS the strict-SAS acknowledgement. The
/// backend's `POST /confirm` requires
/// `comparison_acknowledged: true` on the wire, and our service
/// hard-codes that — but the gate the user sees is the warning
/// banner + clearly-labelled button, not a redundant Toggle.
///
/// (Pre-refactor S156 plan had a checkbox; replaced after
/// auditing upstream `SessionVerificationScreen` — see
/// DECISIONS.md S156 for the rationale.)
class VerificationDetailScreenViewModel: VerificationDetailScreenViewModelType, VerificationDetailScreenViewModelProtocol {
    private let verificationID: String
    private let agentPlatformService: any AgentPlatformServiceProtocol

    private let actionsSubject: PassthroughSubject<VerificationDetailScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<VerificationDetailScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(verificationID: String,
         agentPlatformService: any AgentPlatformServiceProtocol,
         initialDetailState: VerificationDetailState = .loading,
         initialRequesterUserID: String = "",
         initialRequesterDeviceID: String? = nil,
         initialDeadlineAt: Date? = nil) {
        self.verificationID = verificationID
        self.agentPlatformService = agentPlatformService
        // Optional seed parameters let SwiftUI previews and unit
        // tests render any state without exercising the network.
        // Production code always uses the defaults and lets
        // `.appeared` drive the fetch.
        var initial = VerificationDetailScreenViewState(bindings: VerificationDetailScreenViewStateBindings())
        initial.detailState = initialDetailState
        initial.requesterUserID = initialRequesterUserID
        initial.requesterDeviceID = initialRequesterDeviceID
        initial.deadlineAt = initialDeadlineAt
        super.init(initialViewState: initial)
    }

    // MARK: - Public

    override func process(viewAction: VerificationDetailScreenViewAction) {
        MXLog.info("VerificationDetailScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            // Skip refetch if we already landed on a terminal
            // state in this screen's lifetime (user is just
            // looking before dismissing).
            if state.detailState.isTerminalForFetch {
                return
            }
            Task { await loadDetail() }
        case .refresh:
            Task { await loadDetail() }
        case .confirm:
            Task { await runConfirm() }
        case .reject:
            Task { await runReject() }
        case .done:
            actionsSubject.send(.dismissed)
        }
    }

    // MARK: - Private — actions

    private func loadDetail() async {
        // Preserve emojis across refresh if we already have
        // them — keeps the screen from flickering to a
        // skeleton while the user pulls-to-refresh.
        if !state.detailState.isTerminalForFetch {
            state.detailState = .loading
        }

        switch await agentPlatformService.fetchVerification(id: verificationID) {
        case .success(let detail):
            apply(detail: detail)
        case .failure(let error):
            // 404 on the initial GET = the row was just
            // cancelled; render as cancelled rather than as a
            // generic failure so the user gets the right
            // mental model.
            if case .notFound = error {
                state.detailState = .cancelled(reason: nil)
                return
            }
            MXLog.error("VerificationDetailScreenViewModel: fetch failed: \(error)")
            state.detailState = .failed(reason: error.description)
            state.bindings.alertInfo = AlertInfo(id: .fetchFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                     Task { await self?.loadDetail() }
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }

    private func runConfirm() async {
        // Guard: the button should already be disabled by the
        // view if we're not in `.readyForReview`, but defend
        // against the binding lagging behind state mutations.
        guard let emojis = state.detailState.emojis,
              case .readyForReview = state.detailState else {
            return
        }
        state.detailState = .confirming(emojis: emojis)

        switch await agentPlatformService.confirmVerification(id: verificationID) {
        case .success(let detail):
            apply(detail: detail)
            // If wire confirms either of the two happy-path
            // terminal states, bubble to coordinator so it can
            // pop. Otherwise the user lands on the inline
            // success copy and taps Done themselves.
            switch state.detailState {
            case .awaitingRemoteDone, .confirmed:
                actionsSubject.send(.decided)
            default:
                break
            }
        case .failure(let error):
            MXLog.error("VerificationDetailScreenViewModel: confirm failed: \(error)")
            // 409 = OlmMachine no longer tracks the flow
            // (orchestrator restart / remote cancelled /
            // deadline elapsed). Render as cancelled so the
            // user knows to move on, not retry.
            if case .conflict(let detail) = error {
                state.detailState = .cancelled(reason: detail)
                return
            }
            // Revert to ready-for-review so the user can try
            // again (or reject). Non-409 failures are most
            // commonly transport blips.
            state.detailState = .readyForReview(emojis: emojis)
            state.bindings.alertInfo = AlertInfo(id: .confirmFailed,
                                                 title: L10n.commonError,
                                                 message: error.description)
        }
    }

    private func runReject() async {
        guard let emojis = state.detailState.emojis,
              case .readyForReview = state.detailState else {
            return
        }
        state.detailState = .rejecting(emojis: emojis)

        switch await agentPlatformService.rejectVerification(id: verificationID) {
        case .success(let detail):
            apply(detail: detail)
            // Reject always lands the row in cancelled. Once
            // we observe that, bubble to coordinator.
            switch state.detailState {
            case .rejected, .cancelled:
                actionsSubject.send(.decided)
            default:
                break
            }
        case .failure(let error):
            MXLog.error("VerificationDetailScreenViewModel: reject failed: \(error)")
            state.detailState = .readyForReview(emojis: emojis)
            state.bindings.alertInfo = AlertInfo(id: .rejectFailed,
                                                 title: L10n.commonError,
                                                 message: error.description)
        }
    }

    // MARK: - Private — state derivation

    /// Apply a freshly-fetched `VerificationDetail` to view
    /// state. Handles every backend state explicitly so the
    /// view's switch stays simple.
    private func apply(detail: VerificationDetail) {
        state.requesterUserID = detail.requesterUserID
        state.requesterDeviceID = detail.requesterDeviceID
        state.deadlineAt = detail.deadlineAt
        state.detailState = Self.derive(state: detail)
    }

    /// Pure mapper: wire `VerificationDetail` → screen state.
    /// Public on `static` so unit tests can pin the matrix
    /// without instantiating the ViewModel.
    static func derive(state detail: VerificationDetail) -> VerificationDetailState {
        switch detail.state {
        case .pendingDhExchange:
            return .waitingForEmojis
        case .pendingOwner:
            // Defensive: if the backend reports pending_owner
            // but emojis come back nil, fall back to
            // "waiting" rather than rendering an empty grid.
            // Real backend always supplies the array when in
            // pending_owner (asserted by `tests::api_verifications`
            // on the server side) but we defend anyway.
            guard let emojis = detail.emojis, emojis.count == 7 else {
                return .waitingForEmojis
            }
            return .readyForReview(emojis: emojis)
        case .awaitingRemoteDone:
            return .awaitingRemoteDone
        case .confirmed:
            return .confirmed
        case .cancelled:
            return .cancelled(reason: detail.cancelCode)
        case .unknown(let raw):
            return .failed(reason: "unknown verification state: \(raw)")
        }
    }
}

// MARK: - State conveniences

private extension VerificationDetailState {
    /// True iff a refetch would be wasted because we already
    /// landed somewhere we can't transition out of via fetch
    /// alone. Used by `.appeared` to skip the no-op GET when
    /// the user is just re-viewing the screen.
    var isTerminalForFetch: Bool {
        switch self {
        case .awaitingRemoteDone, .rejected, .cancelled, .confirmed:
            return true
        default:
            return false
        }
    }
}
