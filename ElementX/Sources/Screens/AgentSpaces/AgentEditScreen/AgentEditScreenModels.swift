//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// AGENT-PLATFORM: Brief 0037, artboard 0037-G. Decision 194 made it the
// agent's «Изменить профиль»: the avatar (deferred `clientProxy.uploadMedia`
// → PATCH `avatar_mxc`) and the name, nothing else; the rest lives in the
// agent screen's «Настройки». The name's bounds come from the published
// edit-schema (ADR-0049).

enum AgentEditScreenViewModelAction {
    /// Saved — the flow pops and reloads the agent.
    case saved
    case cancel
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
}

struct AgentEditScreenViewState: BindableState {
    let card: AgentSpaceAgentCard

    var loadState: AgentEditScreenLoadState = .loading
    var isSaving = false

    /// The current server avatar (nil after Remove — an explicit clear).
    var avatarMXC: String?
    /// The avatar as loaded (the change baseline).
    var initialAvatarMXC: String?
    /// Deferred replacement, uploaded on Save.
    var localMedia: MediaInfo?
    /// The name as the server holds it (the change baseline).
    var initialDisplayName = ""

    var bindings = AgentEditScreenViewStateBindings()

    var schema: AgentEditSchema? {
        if case .loaded(let schema) = loadState { return schema }
        return nil
    }

    var displayNameValid: Bool {
        guard let bounds = schema?.displayName else { return false }
        let count = bindings.displayName.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        return count >= bounds.minLength && count <= bounds.maxLength
    }

    var nameDidChange: Bool {
        bindings.displayName.trimmingCharacters(in: .whitespacesAndNewlines) != initialDisplayName
    }

    var avatarDidChange: Bool {
        localMedia != nil || avatarMXC != initialAvatarMXC
    }

    /// RoomDetailsEdit canon: valid AND something actually changed.
    var canSave: Bool {
        schema != nil && displayNameValid && !isSaving && (avatarDidChange || nameDidChange)
    }

    var showDeleteImageAction: Bool {
        localMedia != nil || avatarMXC != nil
    }
}

/// The name's limits. The form doesn't wait for them: its values come from the card and the store.
nonisolated enum AgentEditScreenLoadState: Equatable {
    case loading
    case loaded(AgentEditSchema)
    case failure
}

struct AgentEditScreenViewStateBindings {
    var displayName = ""
    var showMediaSheet = false
    var alertInfo: AlertInfo<AgentEditScreenAlertType>?
}

enum AgentEditScreenAlertType: Hashable {
    case saveFailed
    case failedProcessingMedia
    case failedUploadingAvatar
    case unsavedChanges
}

enum AgentEditScreenViewAction {
    case save
    case cancel
    case retry
    case presentMediaSource
    case displayCameraPicker
    case displayMediaPicker
    case displayFilePicker
    case removeImage
}

extension AgentPlatformError {
    /// Why the backend refused an agent's name on a create or rename; `nil` for any other failure.
    var agentNameRefusal: String? {
        switch self {
        case .displayNameReserved: UntranslatedL10n.errorAgentNameReserved
        case .displayNameInvalidCharacters: UntranslatedL10n.errorAgentNameInvalidCharacters
        case .displayNameUnchecked: UntranslatedL10n.errorAgentNameUnchecked
        default: nil
        }
    }
}
