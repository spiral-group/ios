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

// MARK: - ViewModel → Coordinator actions

enum VerificationDetailScreenViewModelAction {
    /// Decision was applied (confirm OR reject) and the wire
    /// returned 2xx. Coordinator pops the screen; the list
    /// re-renders on its next `.appeared` (or pull-to-refresh).
    case decided
    /// User tapped Done after the request was found terminal
    /// (e.g. backend reports already-confirmed / cancelled by
    /// remote). Coordinator pops without expecting the list to
    /// re-fetch — there's nothing actionable left.
    case dismissed
}

// MARK: - View ↔ ViewModel state

/// Detail screen's modal state. Models the lifecycle of a
/// SINGLE verification approval from REST fetch through
/// terminal decision. Adapted from upstream
/// `SessionVerificationScreenStateMachine.State` but trimmed for
/// our owner-proxy use-case: we don't drive the SDK SAS flow
/// directly (the orchestrator's `OlmMachine` does), we just
/// fetch the row and confirm/reject. Hence fewer "requesting" /
/// "starting" transition states.
enum VerificationDetailState: Equatable {
    /// First fetch in flight. No data yet.
    case loading
    /// Fetched, but the backend reports
    /// `pending_dh_exchange` — emojis aren't ready. The view
    /// renders a "waiting for emojis" placeholder + a manual
    /// refresh button. Auto-refetch isn't wired (rare event);
    /// the user can pull-to-refresh once the requester clicks
    /// through their side.
    case waitingForEmojis
    /// Backend reports `pending_owner`, emojis arrived. The
    /// view renders the 7-emoji grid + match / don't-match
    /// buttons. This is the only actionable state — every
    /// other state shows informational chrome only.
    case readyForReview(emojis: [VerificationEmoji])
    /// POST `/confirm` in flight. Buttons disabled, spinner
    /// on the "They match" button.
    case confirming(emojis: [VerificationEmoji])
    /// POST `/reject` in flight. Buttons disabled, spinner
    /// on the "They don't match" button.
    case rejecting(emojis: [VerificationEmoji])
    /// Wire returned 200 on confirm — flow is now waiting on
    /// the remote side to send `m.key.verification.done`.
    /// Terminal from this screen's perspective; the view
    /// renders a success header + dismiss button.
    case awaitingRemoteDone
    /// Wire returned 200 on reject. Terminal.
    case rejected
    /// Wire returned 409 (request gone) or the backend's
    /// detail GET reported `cancelled`. Terminal.
    case cancelled(reason: String?)
    /// Wire returned 200 with `state == confirmed` — the
    /// remote side already completed the flow before we got
    /// here. Terminal.
    case confirmed
    /// Wire returned 4xx/5xx other than the expected codes,
    /// or the initial GET failed. Renders an inline error +
    /// retry button. Distinct from `.cancelled` so the user
    /// can retry the fetch (vs the row being truly gone).
    case failed(reason: String)
}

extension VerificationDetailState {
    /// Convenience: true iff a network call is in flight.
    /// Drives `.disabled` on the action buttons + spinners
    /// in their accessory views.
    var isInFlight: Bool {
        switch self {
        case .loading, .confirming, .rejecting: return true
        default: return false
        }
    }

    /// Convenience: emojis if this state carries them.
    /// `nil` for waiting-for-emojis and all terminal states.
    var emojis: [VerificationEmoji]? {
        switch self {
        case .readyForReview(let e), .confirming(let e), .rejecting(let e):
            return e
        default:
            return nil
        }
    }
}

struct VerificationDetailScreenViewState: BindableState {
    var detailState: VerificationDetailState = .loading
    /// MXID of the requester. Stable across state transitions;
    /// rendered in the header even while the emoji panel is
    /// loading.
    var requesterUserID = ""
    /// Optional device ID for the requester. Surfaced under
    /// the MXID as a small secondary label.
    var requesterDeviceID: String?
    /// Set once the initial fetch returns. Drives the
    /// "expires in 4m 32s" relative countdown in the header.
    /// Nil while still loading.
    var deadlineAt: Date?

    var bindings: VerificationDetailScreenViewStateBindings
}

struct VerificationDetailScreenViewStateBindings {
    var alertInfo: AlertInfo<VerificationDetailScreenAlertType>?
}

enum VerificationDetailScreenAlertType: Hashable {
    case fetchFailed
    case confirmFailed
    case rejectFailed
}

// MARK: - View → ViewModel actions

enum VerificationDetailScreenViewAction {
    /// SwiftUI `.onAppear`. Triggers the initial GET.
    case appeared
    /// Pull-to-refresh or inline retry button. Re-fetches the
    /// row (useful in `.waitingForEmojis` to pick up the
    /// `pending_owner` transition).
    case refresh
    /// User tapped "They match" — POSTs to `/confirm`. The
    /// implementing service hard-codes
    /// `comparison_acknowledged: true`; the UX gate is the
    /// distinct button label + warning header above, NOT a
    /// separate checkbox (matches upstream
    /// `SessionVerificationScreen` UX).
    case confirm
    /// User tapped "They don't match" — POSTs to `/reject`.
    case reject
    /// User tapped Done on a terminal state.
    case done
}
