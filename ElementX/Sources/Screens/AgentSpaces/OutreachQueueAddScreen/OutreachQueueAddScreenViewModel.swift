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

typealias OutreachQueueAddScreenViewModelType = StateStoreViewModelV2<OutreachQueueAddScreenViewState, OutreachQueueAddScreenViewAction>

/// Drives `OutreachQueueAddScreen`. Parses the multi-line
/// textarea into MXIDs on submit; POSTs the batch; renders
/// the per-item result table.
///
/// ### Why parse + submit in one shot (no per-line live
/// validation)
///
/// The backend already enforces MXID shape per row +
/// returns `EnqueueItemOutcome.invalid(reason: …)` for
/// failures. Mirroring that validation client-side would
/// duplicate the rule + create two sources of truth. We
/// just send the trimmed lines + let the server pronounce
/// per item.
///
/// ### Cancel-with-buffer UX
///
/// Same pattern as `RoleBriefEditorScreen` (S179): cancel
/// raises an unsaved-changes alert when the buffer has any
/// non-empty content. After a successful submit, the user
/// reads the summary table + taps Done; we don't auto-pop.
class OutreachQueueAddScreenViewModel: OutreachQueueAddScreenViewModelType, OutreachQueueAddScreenViewModelProtocol {
    private let agentID: String
    private let agentPlatformService: any AgentPlatformServiceProtocol

    private let actionsSubject: PassthroughSubject<OutreachQueueAddScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<OutreachQueueAddScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    init(agentID: String,
         agentPlatformService: any AgentPlatformServiceProtocol,
         initialState: OutreachQueueAddState = .draft,
         initialText: String = "") {
        self.agentID = agentID
        self.agentPlatformService = agentPlatformService
        var bindings = OutreachQueueAddScreenViewStateBindings()
        bindings.draftText = initialText
        var initial = OutreachQueueAddScreenViewState(agentID: agentID, bindings: bindings)
        initial.detailState = initialState
        super.init(initialViewState: initial)
    }

    override func process(viewAction: OutreachQueueAddScreenViewAction) {
        MXLog.info("OutreachQueueAddScreenViewModel received view action: \(viewAction)")

        switch viewAction {
        case .submit:
            Task { await runSubmit() }
        case .cancel:
            handleCancel()
        case .discardChanges:
            actionsSubject.send(.dismissed)
        case .dismiss:
            actionsSubject.send(.dismissed)
        }
    }

    private func runSubmit() async {
        let lines = OutreachQueueAddScreenViewState.parseLines(state.bindings.draftText)
        guard !lines.isEmpty else {
            MXLog.warning("OutreachQueueAddScreenViewModel: submit with empty buffer; ignoring")
            return
        }
        guard lines.count <= OutreachQueueAddScreenViewState.maxBatchSize else {
            MXLog.warning("OutreachQueueAddScreenViewModel: submit over cap; ignoring")
            return
        }

        state.detailState = .submitting

        switch await agentPlatformService.enqueueOutreachTargets(agentID: agentID, mxids: lines) {
        case .success(let result):
            state.detailState = .results(result)
            actionsSubject.send(.enqueued(result))
        case .failure(let error):
            MXLog.error("OutreachQueueAddScreenViewModel: enqueue failed: \(error)")
            switch error {
            case .conflict(let detail):
                state.detailState = .unavailable(reason: detail)
            case .notFound:
                state.detailState = .unavailable(reason: "agent not found")
            default:
                state.detailState = .failed(reason: error.description)
                state.bindings.alertInfo = AlertInfo(id: .submitFailed,
                                                     title: L10n.commonError,
                                                     message: error.description)
            }
        }
    }

    private func handleCancel() {
        let trimmed = state.bindings.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || state.detailState.isTerminalAfterSubmit {
            actionsSubject.send(.dismissed)
            return
        }
        state.bindings.alertInfo = AlertInfo(id: .unsavedChanges,
                                             title: UntranslatedL10n.screenOutreachQueueAddUnsavedTitle,
                                             message: UntranslatedL10n.screenOutreachQueueAddUnsavedSubtitle,
                                             primaryButton: .init(title: UntranslatedL10n.screenOutreachQueueAddUnsavedDiscard,
                                                                  role: .destructive) { [weak self] in
                                                 self?.actionsSubject.send(.dismissed)
                                             },
                                             secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }
}
