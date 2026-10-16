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

enum OutreachQueueAddScreenViewModelAction {
    /// Enqueue succeeded; the result drives an inline summary
    /// table. We don't auto-dismiss because the user wants to
    /// read the per-row outcomes (some lines were queued, some
    /// were dupes, some invalid).
    case enqueued(EnqueueOutreachResult)
    /// User tapped Done on the post-submit summary.
    case dismissed
}

// MARK: - View ↔ ViewModel state

/// Pre-submit / submitting / post-submit phases. The "draft"
/// state owns the editor; "results" owns the post-submit
/// summary table.
enum OutreachQueueAddState: Equatable {
    /// Editor open, user typing.
    case draft
    /// POST in flight; textarea + Save button disabled.
    case submitting
    /// Wire returned 200. Render the per-row outcome table +
    /// summary chips.
    case results(EnqueueOutreachResult)
    /// 409 — agent isn't outreach-kind. Terminal: dashboard
    /// shouldn't have routed here in the first place.
    case unavailable(reason: String)
    /// Wire returned 4xx/5xx; preserve the editor buffer so
    /// the user can retry.
    case failed(reason: String)
}

extension OutreachQueueAddState {
    var isInFlight: Bool {
        if case .submitting = self { return true }
        return false
    }

    var isTerminalAfterSubmit: Bool {
        switch self {
        case .results, .unavailable:
            return true
        default:
            return false
        }
    }
}

struct OutreachQueueAddScreenViewState: BindableState {
    let agentID: String
    var detailState: OutreachQueueAddState = .draft
    var bindings: OutreachQueueAddScreenViewStateBindings

    /// Parsed line count of the live buffer. Drives the
    /// "37 / 200" counter under the textarea.
    ///
    /// Counts non-empty trimmed lines only. A trailing newline
    /// or whitespace-only line doesn't bump the counter.
    var parsedCount: Int {
        Self.parseLines(bindings.draftText).count
    }

    /// `true` when the buffer is past the 200-MXID cap.
    var isOverLimit: Bool {
        parsedCount > OutreachQueueAddScreenViewState.maxBatchSize
    }

    /// Server caps the batch at 200 (`MAX_BATCH_SIZE` const
    /// in backend `outreach_queue.rs`); iOS mirrors here so
    /// the editor disables Save before the round-trip
    /// rejects a 5000-line paste.
    static let maxBatchSize = 200

    /// Splits the buffer into trimmed non-empty lines. Public-
    /// on-`static` so the view model + unit tests share one
    /// parse implementation.
    ///
    /// Order-preserving + dedup-naive (the backend collapses
    /// in-batch duplicates and reports them as `duplicate` —
    /// iOS doesn't pre-filter because the result table
    /// SHOULD show "you typed this twice").
    static func parseLines(_ buffer: String) -> [String] {
        buffer
            .split { $0.isNewline }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct OutreachQueueAddScreenViewStateBindings {
    /// Live textarea content. One MXID per line.
    var draftText = ""
    var alertInfo: AlertInfo<OutreachQueueAddScreenAlertType>?
}

enum OutreachQueueAddScreenAlertType: Hashable {
    case submitFailed
    case unsavedChanges
}

// MARK: - View → ViewModel actions

enum OutreachQueueAddScreenViewAction {
    /// User tapped Save. ViewModel parses + validates the
    /// buffer + POSTs.
    case submit
    /// User tapped Cancel / back. Raises an unsaved-changes
    /// alert when the buffer has anything in it.
    case cancel
    /// User confirmed "discard" on the unsaved alert.
    case discardChanges
    /// User tapped Done on the post-submit summary.
    case dismiss
}
