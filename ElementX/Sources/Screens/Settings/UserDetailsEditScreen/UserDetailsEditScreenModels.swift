//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum UserDetailsEditScreenViewModelAction {
    case dismiss
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
}

struct UserDetailsEditScreenViewState: BindableState {
    var currentUserProfile: UserProfile
    
    var canEditAvatar = true
    var canEditDisplayName = true
    
    var selectedAvatarURL: URL?
    var localMedia: MediaInfo?
    
    // AGENT-PLATFORM: feed (Brief 0082, decision 284). Brief 0083, question 359: `.loading` from the
    // first frame, so the section stands before the server answers; only a refusal takes it away.
    var bio: UserDetailsEditBioState = .loading
    
    var bindings: UserDetailsEditScreenViewStateBindings
    
    var nameDidChange: Bool {
        bindings.name != currentUserProfile.displayName
    }
    
    var avatarDidChange: Bool {
        localMedia != nil || selectedAvatarURL != currentUserProfile.avatarURL
    }
    
    // AGENT-PLATFORM: feed (Brief 0082): only a loaded bio can change; one that failed to load is never overwritten.
    var bioDidChange: Bool {
        guard case let .loaded(savedBio) = bio else { return false }
        let saved = savedBio ?? ""
        // Untouched is no change, even when the saved bio isn't normalised; nor is what normalises back to it.
        return bindings.bio != saved && normalisedBio != saved
    }
    
    /// What the bio saves as, normalised as the backend shows it (`FeedBio`); empty removes it.
    var normalisedBio: String {
        FeedBio.normalised(bindings.bio)
    }
    
    var bioLength: Int {
        normalisedBio.count
    }
    
    var isBioTooLong: Bool {
        bioLength > FeedBio.maxLength
    }
    
    var canSave: Bool {
        // AGENT-PLATFORM: feed (Brief 0082): the bio's change and its limit. Only a changed bio is saved, so only a
        // changed one that is too long holds Save back, and the footer says to shorten it.
        !bindings.name.isEmpty && (avatarDidChange || nameDidChange || bioDidChange) && !(bioDidChange && isBioTooLong)
    }
    
    var showDeleteImageAction: Bool {
        localMedia != nil || selectedAvatarURL != nil
    }
}

// AGENT-PLATFORM: feed (Brief 0082, decision 284): the bio field's state.
nonisolated enum UserDetailsEditBioState: Equatable {
    /// The server doesn't allow the field, or the check failed: no field.
    case unavailable
    case loading
    /// The read failed: the field says so and offers a retry, never an empty bio to save.
    case loadFailed
    /// The server's bio, `nil` when none is set.
    case loaded(String?)
}

struct UserDetailsEditScreenViewStateBindings {
    var name = ""
    // AGENT-PLATFORM: feed (Brief 0082)
    var bio = ""
    var showMediaSheet = false
    
    var alertInfo: AlertInfo<UserDetailsEditScreenAlertType>?
}

enum UserDetailsEditScreenAlertType {
    case failedProcessingMedia
    case unsavedChanges
    case saveError
    // AGENT-PLATFORM: feed (Brief 0082)
    case bioSaveError
    case unknown
}

enum UserDetailsEditScreenViewAction {
    case cancel
    case save
    case presentMediaSource
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
    case removeImage
    // AGENT-PLATFORM: feed (Brief 0082)
    case retryLoadingBio
}
