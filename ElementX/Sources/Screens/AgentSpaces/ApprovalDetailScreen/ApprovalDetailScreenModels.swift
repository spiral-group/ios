//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.

import Foundation

enum ApprovalDetailScreenViewModelAction {
    /// Decision posted + delivery confirmed; coordinator should
    /// pop the screen and let the list re-render via the SSE
    /// `decided` event that's already in flight.
    case decisionFinalised
}

/// State of the underlying fetch + decide pipeline.
enum ApprovalDetailScreenLoadState: Equatable {
    case loading
    case loaded(ApprovalDetail)
    case failed(reason: String)
}

/// Tracks an in-flight decide call. Drives spinner + disables
/// the action buttons so the user can't double-tap. The
/// `decision` payload is preserved so we can render a "Retry"
/// affordance on `send_failed` without re-asking the user for
/// (e.g.) the edit body.
enum ApprovalDetailScreenDecideState: Equatable {
    case idle
    case submitting(ApprovalDecision)
    /// Delivery succeeded — UI shows a brief success state
    /// before the coordinator pops. Carries the outcome so
    /// previews + tests can verify.
    case succeeded(ApprovalDecisionResult)
    /// Decision was recorded but the final Matrix send failed.
    /// User can retry (calls `decide` again with the same
    /// `decision`) or dismiss (pops the screen — backend
    /// already has the decision logged, just the wire send
    /// didn't land).
    case sendFailed(decision: ApprovalDecision, reason: String)
}

struct ApprovalDetailScreenViewState: BindableState {
    var loadState: ApprovalDetailScreenLoadState = .loading
    var decideState: ApprovalDetailScreenDecideState = .idle
    var bindings: ApprovalDetailScreenViewStateBindings
    /// A block request's person by name, once this client has read their
    /// profile; the card shows the MXID until then, or without one.
    var blockTargetDisplayName: String?
    /// A block request's group by name, when the owner is in it.
    var blockRoomName: String?
    /// The room the draft goes to, as the owner reads it (`AgentRoomLabel`).
    var targetRoomName: String?

    /// Convenience: is any decide operation in flight? Disables
    /// the action buttons to prevent double-submission.
    var isDecideInFlight: Bool {
        if case .submitting = decideState { return true }
        return false
    }

    /// The block request was approved and the contact is blocked.
    var isBlocked: Bool {
        if case .succeeded(let result) = decideState, result.delivery == .applied { return true }
        return false
    }
}

struct ApprovalDetailScreenViewStateBindings {
    var alertInfo: AlertInfo<ApprovalDetailScreenAlertType>?
    /// Edit-mode draft text. Populated from the loaded
    /// approval's `draftBody` when the user enters edit mode;
    /// committed back via `.commitEdit`.
    var editBuffer = ""
    /// `true` while the user is editing the draft text. The
    /// view swaps the "Edit" CTA for "Save changes" + a
    /// "Cancel" button when this is set.
    var isEditing = false
}

enum ApprovalDetailScreenAlertType: Hashable {
    case fetchFailed
    case decideFailed
    /// The decision is recorded; the Matrix send did not land.
    case sendFailed
    /// The block was not saved (500); the request is still pending.
    case blockFailed
    /// The approve was refused: the owner blocked the person, and the
    /// platform closed the card (expired). Nothing was sent.
    case targetBlocked
    /// The card is gone (404): its person was erased, so it was deleted and
    /// nothing was sent.
    case notFound
    /// The approve or edit was refused: the agent is paused. The card stays pending.
    case agentPaused
}

enum ApprovalDetailScreenViewAction {
    /// SwiftUI `.onAppear`. Triggers the initial fetch.
    case appeared
    case retryFetch
    case approve
    case reject
    /// Toggle from read-only into edit mode. Pre-fills
    /// `editBuffer` from the current draft.
    case beginEdit
    case cancelEdit
    /// Submit the current `editBuffer` as an `edit` decision.
    case commitEdit
    /// Retry a `send_failed` decision with the same payload.
    case retryDecide
    /// Dismiss the screen after a `send_failed` without
    /// retrying — the backend has the decision logged, the
    /// final wire send is the orchestrator's problem.
    case dismissAfterSendFailure
    /// Leave a block request once it reads "Blocked".
    case done
}
