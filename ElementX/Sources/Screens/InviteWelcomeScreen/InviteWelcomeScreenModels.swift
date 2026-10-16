//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//


import Foundation

enum InviteWelcomeScreenViewModelAction: Equatable {
    case openDirectChat(roomID: String)
    case dismiss
}

struct InviteWelcomeScreenViewState: BindableState {
    let inviterUserID: String
    var inviterProfile: UserProfile?
    var isOpeningChat = false
    var bindings = InviteWelcomeScreenViewStateBindings()
    
    /// The display name, else the MXID's localpart — never the full MXID in a title.
    var inviterName: String {
        if let name = inviterProfile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return inviterUserID.dropFirst().split(separator: ":").first.map(String.init) ?? inviterUserID
    }
}

struct InviteWelcomeScreenViewStateBindings {
    var alertInfo: AlertInfo<InviteWelcomeScreenAlertType>?
}

enum InviteWelcomeScreenAlertType: Hashable {
    case failedOpeningChat
}

enum InviteWelcomeScreenViewAction {
    case message
    case later
}
