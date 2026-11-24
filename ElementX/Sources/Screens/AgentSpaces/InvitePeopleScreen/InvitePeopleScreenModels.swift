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
    /// 1.0.3 (concept C, operator 2026-11-21): the caller, the middle of the chain — whose link they came by above,
    /// who came by theirs below.
    var ownProfile: UserProfile
    var invite: MyInvite?
    var isLoading = true
    /// Who registered through the caller's links, newest first.
    var joined: [UserProfile] = []
    /// 1.0.3 (operator 2026-11-21: «щоб бачили і другу сторону»): whose link the caller registered with, if a person's.
    var invitedBy: UserProfile?
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
    
    /// The link's seats in order: who came, the taken seats the list doesn't name, then the free ones — the first of
    /// them the way to invite. While the link's read is out, its seats wait at the count every link has.
    var seats: [InviteSeat] {
        guard let invite else {
            return isLoadingInvite ? (0..<Self.seatsWhileLoading).map { .loading($0) } : []
        }
        var seats = joined.prefix(invite.maxUses).map { InviteSeat.joined($0) }
        seats += (0..<joinedPlaceholderCount).map { .loading($0) }
        // The link counts seats the list of who came doesn't name: someone mid sign-up, an account since deleted (its
        // seat stays counted, nameless — migration 0078), or a list that failed to load. The client can't tell them
        // apart, so they are just taken.
        let taken = max(0, invite.used - joined.count - joinedPlaceholderCount)
        seats += (0..<min(taken, invite.maxUses - seats.count)).map { .taken($0) }
        let free = max(0, invite.maxUses - seats.count)
        seats += (0..<free).map { $0 == 0 ? .invite : .free($0) }
        return seats
    }
    
    /// Every link has ten seats (the operator, 2026-10-06).
    static let seatsWhileLoading = 10
}

/// One seat of the caller's link.
enum InviteSeat: Hashable, Identifiable {
    case joined(UserProfile)
    /// A person the link counts whose profile is still being read, or a seat of a link still being read.
    case loading(Int)
    /// A seat the link counts that the list of who came doesn't name.
    case taken(Int)
    /// The first free seat: a tap shares the link.
    case invite
    case free(Int)
    
    /// A person keeps their seat's identity when their name lands.
    var id: String {
        switch self {
        case .joined(let user): "joined:\(user.id)"
        case .loading(let index): "loading:\(index)"
        case .taken(let index): "taken:\(index)"
        case .invite: "invite"
        case .free(let index): "free:\(index)"
        }
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
