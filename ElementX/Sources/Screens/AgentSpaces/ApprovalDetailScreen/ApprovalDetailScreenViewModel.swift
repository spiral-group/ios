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

typealias ApprovalDetailScreenViewModelType = StateStoreViewModelV2<ApprovalDetailScreenViewState, ApprovalDetailScreenViewAction>

/// Drives `ApprovalDetailScreen`. Fetches one approval on
/// `.appeared`, then handles the three decision verbs (approve /
/// reject / edit). The `send_failed` delivery outcome is treated
/// specially: backend has the decision logged but the wire send
/// didn't land, so the UI keeps the screen open and offers a
/// retry CTA instead of popping.
///
/// The approval is the one consent record (ADR-0087): every
/// escalation the owner decides — a first contact's included —
/// arrives here by its approval id.
///
/// A block request (decision 38) sends nothing: approve or reject, no
/// edit; an `applied` approve keeps the card up reading "Blocked", and a
/// 500 leaves it pending to approve again.
///
/// An approve or edit of a cold-outreach card to someone the owner blocked
/// is refused (409 `/errors/target-blocked`) and the card closed: the owner
/// reads "Not sent — you blocked this person" and OK leaves the card.
class ApprovalDetailScreenViewModel: ApprovalDetailScreenViewModelType, ApprovalDetailScreenViewModelProtocol {
    private let approvalID: String
    private let agentPlatformService: any AgentPlatformServiceProtocol
    private let clientProxy: any ClientProxyProtocol

    private let actionsSubject: PassthroughSubject<ApprovalDetailScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<ApprovalDetailScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(approvalID: String,
         agentPlatformService: any AgentPlatformServiceProtocol,
         clientProxy: any ClientProxyProtocol) {
        self.approvalID = approvalID
        self.agentPlatformService = agentPlatformService
        self.clientProxy = clientProxy
        super.init(initialViewState: ApprovalDetailScreenViewState(bindings: ApprovalDetailScreenViewStateBindings()))
    }

    // MARK: - Public

    override func process(viewAction: ApprovalDetailScreenViewAction) {
        MXLog.info("ApprovalDetailScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .appeared:
            // Re-appears after a successful fetch skip the
            // round-trip; the SSE service is the canonical
            // refresh channel and the parent list seeds us with
            // fresh data when the user navigates here.
            if case .loaded = state.loadState { return }
            Task { await loadApproval() }
        case .retryFetch:
            Task { await loadApproval() }
        case .approve:
            Task { await submitDecision(.approve) }
        case .reject:
            Task { await submitDecision(.reject) }
        case .beginEdit:
            // The platform refuses to edit a block request (400): there is no message.
            guard case .loaded(let detail) = state.loadState, !detail.isBlockRequest else { return }
            state.bindings.editBuffer = detail.draftBody
            state.bindings.isEditing = true
        case .cancelEdit:
            state.bindings.isEditing = false
            state.bindings.editBuffer = ""
        case .commitEdit:
            let body = state.bindings.editBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            Task { await submitDecision(.edit(newBody: body)) }
        case .retryDecide:
            guard case .sendFailed(let decision, _) = state.decideState else { return }
            Task { await submitDecision(decision) }
        case .dismissAfterSendFailure, .done:
            actionsSubject.send(.decisionFinalised)
        }
    }

    // MARK: - Private

    private func loadApproval() async {
        state.loadState = .loading
        switch await agentPlatformService.fetchApproval(id: approvalID) {
        case .success(let detail):
            state.targetRoomName = AgentRoomLabel.text(for: detail.targetRoomID, clientProxy: clientProxy)
            state.loadState = .loaded(detail)
            if case .blockSender(let request) = detail.context {
                await resolveNames(of: request)
            }
        case .failure(let error):
            MXLog.error("ApprovalDetailScreenViewModel: fetch failed: \(error)")
            state.loadState = .failed(reason: error.description)
            if case .approvalNotFound = error {
                // Opened after it was deleted (a push, a stale list): nothing to retry.
                showCardGoneAlert()
                return
            }
            state.bindings.alertInfo = AlertInfo(id: .fetchFailed,
                                                 title: L10n.commonError,
                                                 message: L10n.errorUnknown,
                                                 primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                     Task { await self?.loadApproval() }
                                                 },
                                                 secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
        }
    }

    private func submitDecision(_ decision: ApprovalDecision) async {
        state.decideState = .submitting(decision)
        // Reset edit-mode if we're approving an edit; the
        // editor sheet collapses while the spinner spins.
        if case .edit = decision { state.bindings.isEditing = false }

        switch await agentPlatformService.decideApproval(id: approvalID, decision: decision) {
        case .success(let result):
            switch result.delivery {
            case .sent, .notSent, .deferred:
                state.decideState = .succeeded(result)
                actionsSubject.send(.decisionFinalised)
            case .applied:
                state.decideState = .succeeded(result)
                // The block card reads "Blocked" until the owner leaves it; any other
                // card (a block request without its person) has no such state.
                if !isBlockRequest {
                    actionsSubject.send(.decisionFinalised)
                }
            case .sendFailed(let reason):
                MXLog.warning("ApprovalDetailScreenViewModel: send_failed: \(reason)")
                state.decideState = .sendFailed(decision: decision, reason: reason)
                // Retry / Done as an alert (the NotificationSettingsEdit
                // retry pattern), not a card with two buttons in the form.
                state.bindings.alertInfo = AlertInfo(id: .sendFailed,
                                                     title: UntranslatedL10n.screenApprovalDetailSendFailedTitle,
                                                     message: UntranslatedL10n.screenApprovalDetailSendFailedSubtitle,
                                                     primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                         self?.process(viewAction: .retryDecide)
                                                     },
                                                     secondaryButton: .init(title: L10n.actionDone, role: .cancel) { [weak self] in
                                                         self?.process(viewAction: .dismissAfterSendFailure)
                                                     })
            }
        case .failure(let error):
            MXLog.error("ApprovalDetailScreenViewModel: decide failed: \(error)")
            state.decideState = .idle
            if decision == .approve, isBlockRequest, case .serverError(status: 500) = error {
                // The platform rolled the block back; the request is still pending.
                state.bindings.alertInfo = AlertInfo(id: .blockFailed,
                                                     title: UntranslatedL10n.screenApprovalDetailBlockFailedTitle,
                                                     message: UntranslatedL10n.screenApprovalDetailBlockFailedMessage,
                                                     primaryButton: .init(title: L10n.actionRetry) { [weak self] in
                                                         self?.process(viewAction: .approve)
                                                     },
                                                     secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
                return
            }
            if case .targetBlocked = error {
                // The platform closed the card instead (expired, nothing sent): OK leaves it.
                state.bindings.alertInfo = AlertInfo(id: .targetBlocked,
                                                     title: UntranslatedL10n.screenApprovalDetailTargetBlockedTitle,
                                                     message: UntranslatedL10n.screenApprovalDetailTargetBlockedMessage,
                                                     primaryButton: .init(title: L10n.actionOk) { [weak self] in
                                                         self?.actionsSubject.send(.decisionFinalised)
                                                     })
                return
            }
            if case .approvalNotFound = error {
                // A bare 404 says nothing about the card and keeps the generic error.
                showCardGoneAlert()
                return
            }
            if case .agentPaused = error {
                // Nothing was decided: the card stays, to approve after the resume.
                state.bindings.alertInfo = AlertInfo(id: .agentPaused,
                                                     title: UntranslatedL10n.screenApprovalDetailAgentPausedTitle,
                                                     message: UntranslatedL10n.screenApprovalDetailAgentPausedMessage)
                return
            }
            state.bindings.alertInfo = AlertInfo(id: .decideFailed,
                                                 title: L10n.commonError,
                                                 message: error.description)
        }
    }

    /// The card is gone (its person was erased, so it was deleted; nothing was
    /// sent): OK leaves it.
    private func showCardGoneAlert() {
        state.bindings.alertInfo = AlertInfo(id: .notFound,
                                             title: UntranslatedL10n.screenApprovalDetailNotFoundTitle,
                                             message: UntranslatedL10n.screenApprovalDetailNotFoundMessage,
                                             primaryButton: .init(title: L10n.actionOk) { [weak self] in
                                                 self?.actionsSubject.send(.decisionFinalised)
                                             })
    }

    private var isBlockRequest: Bool {
        guard case .loaded(let detail) = state.loadState else { return false }
        return detail.isBlockRequest
    }

    /// The snapshot names the person and the room by ID only. The person's
    /// profile is public on the homeserver; the room has a name here only
    /// when the owner is in it, which a visitor's DM with the agent never is.
    private func resolveNames(of request: ApprovalBlockRequest) async {
        if !request.isDirectMessage {
            state.blockRoomName = AgentRoomLabel.name(for: request.roomID, clientProxy: clientProxy)
        }
        guard case .success(let profile) = await clientProxy.profile(for: request.targetMXID),
              let name = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name != request.targetMXID else {
            return
        }
        state.blockTargetDisplayName = name
    }
}
