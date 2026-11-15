//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: invite links (Brief 0073 / ADR-0008).
//

import Foundation

enum InvitePeopleScreenViewModelAction: Equatable {
    /// A person who joined through the link was tapped.
    case openUser(userID: String)
}

struct InvitePeopleScreenViewState: BindableState {
    var invite: MyInvite?
    var isLoading = true
    /// Who registered through the caller's links, newest first.
    var joined: [UserProfile] = []
    var bindings = InvitePeopleScreenViewStateBindings()
    
    var shareText: String? {
        invite.map { UntranslatedL10n.screenInvitePeopleShareMessage($0.link.webURL.absoluteString) }
    }
    
    /// Brief 0083, question 359: the link's read is out. The page has its shape; only the link's values wait.
    var isLoadingInvite: Bool {
        invite == nil && isLoading
    }
    
    /// Who came through the link while their read is out: the link already counts them.
    var joinedPlaceholderCount: Int {
        isLoading && joined.isEmpty ? invite?.used ?? 0 : 0
    }
}

struct InvitePeopleScreenViewStateBindings {
    var alertInfo: AlertInfo<InvitePeopleScreenAlertType>?
}

enum InvitePeopleScreenAlertType: Hashable {
    case loadFailed
}

enum InvitePeopleScreenViewAction {
    case copyLink
    case openUser(UserProfile)
    case retry
}
