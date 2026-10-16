//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0078, GDPR): «Your data» — the account export and
// one call's export, each handed to the share sheet.
//

import Foundation

struct YourDataScreenViewState: BindableState {
    var isExportingAccount = false
    /// The call whose export is being fetched.
    var exportingCallID: String?
    var calls: YourDataScreenCallsState = .loading
    var isLoadingMoreCalls = false

    var bindings = YourDataScreenViewStateBindings()

    /// One export at a time: the share sheet shows one file.
    var isExporting: Bool {
        isExportingAccount || exportingCallID != nil
    }
}

struct YourDataScreenViewStateBindings {
    /// The export the share sheet is showing.
    var exportFile: PersonalDataExportFile?
}

nonisolated enum YourDataScreenCallsState: Equatable {
    case loading
    case loaded([YourDataScreenCall], nextCursor: String?)
    case failure
}

/// A call to export, with its room's name when the person is still in it.
nonisolated struct YourDataScreenCall: Identifiable, Equatable {
    let session: VoiceSessionRecord
    let roomName: String?

    var id: String {
        session.id
    }
}

enum YourDataScreenViewAction {
    case exportAccount
    case exportCall(id: String)
    case loadMoreCalls
    case retryCalls
    /// The share sheet is gone: the file it showed is removed.
    case exportDismissed
}
