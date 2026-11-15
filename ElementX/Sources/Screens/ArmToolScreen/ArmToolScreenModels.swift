//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// One tool's form (question 359): an example of what the kind does, its
// settings and whose messages it takes. It composes a typed Tool (the WHAT,
// `ToolParams`) with a typed Trigger (the WHEN, `TriggerKind`) and arms it
// through the three-layer gate via `POST …/tools` (`tool.arm`), or turns the
// edited tool off via `DELETE …/tools/:id` (`tool.disable`).
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum ArmToolScreenViewModelAction {
    /// The arm (or disable) applied through the gate — the coordinator goes
    /// back to the list of tools, which reads them again.
    case finished
    /// User asked to pick specific room members for a member-carrying
    /// scope — the flow coordinator presents the room-member picker and
    /// feeds the selection back via `applyMemberSelection`.
    case selectMembers(current: [String])
    /// User asked to pick the target language — the flow coordinator
    /// presents the shared language picker (populated with `languages`, the
    /// transport-specific catalog set) and feeds the chosen code back via
    /// `applyLanguageSelection`.
    case selectLanguage(languages: [AgentLanguage], current: String)
}

// MARK: - Domain

/// The audience-scope options the picker offers, in display order. The
/// two member-carrying tags additionally surface a member selector.
enum ArmToolScope: String, CaseIterable, Identifiable, Equatable {
    case anyone
    case nonSelfNonOwner
    case ownerOnly
    case specificSenders
    case everyoneExcept

    var id: String {
        rawValue
    }

    /// Все / Все, кроме меня / Только я / Выбрать людей… (step B.5); «Все,
    /// кроме…» only for a tool that already has it, so an edit can keep it.
    static func offered(current: ArmToolScope) -> [ArmToolScope] {
        allCases.filter { $0 != .everyoneExcept || current == .everyoneExcept }
    }

    var requiresMembers: Bool {
        self == .specificSenders || self == .everyoneExcept
    }
}

// MARK: - View ↔ ViewModel state

struct ArmToolScreenViewState: BindableState {
    let kind: AgentToolKind
    /// True when editing an existing tool: "Save" and "Turn off", and submit is one arm that replaces it.
    let isEditing: Bool
    /// The agent the tool is for, under the title.
    let agentDisplayName: String
    /// The catalogue's languages are on their way, so the language row can't open yet.
    var isLoadingLanguages = false
    var isSubmitting = false
    var bindings: ArmToolScreenViewStateBindings

    var example: ToolExample {
        ToolExample(kind: kind, language: bindings.language)
    }

    /// The scope needs members but none are selected yet → submit blocked.
    var isMissingMembers: Bool {
        showsScopeSelector && bindings.scope.requiresMembers && bindings.members.isEmpty
    }

    /// A free-text field is required but empty/too short → submit blocked.
    var isMissingRequiredText: Bool {
        if kind.needsLanguage {
            return bindings.language.trimmed.isEmpty
        }
        if kind.needsInstruction {
            return bindings.instruction.trimmed.count < 2
        }
        return false
    }

    var canSubmit: Bool {
        !isMissingMembers && !isMissingRequiredText && !isSubmitting
    }

    /// The call tools take every call, so they have no one to choose (ADR-0094 A.5: `anyone` for live translation).
    var showsScopeSelector: Bool {
        !kind.firesOnCalls
    }

    /// The localized display name for a stored canonical code.
    func displayName(forLanguageCode code: String) -> String {
        TranslationLanguageDisplayName.localizedName(for: code)
    }
}

struct ArmToolScreenViewStateBindings {
    /// Target language (used by `translate` and `live_translate`).
    var language = ""
    /// Free-text instruction (used by `rephrase` + `custom`).
    var instruction = ""
    /// Audience scope for the trigger.
    var scope: ArmToolScope = .anyone
    /// Concrete MXIDs for a member-carrying scope.
    var members: [String] = []

    var alertInfo: AlertInfo<ArmToolScreenAlertType>?
}

enum ArmToolScreenAlertType: Hashable {
    case armFailed
    case disableFailed
    /// "Turn off" asks first: one tap turns the tool off for everyone in the chat.
    case confirmTurnOff
    /// The catalogue couldn't be read, so there is no language to pick from.
    case languagesFailed
}

// MARK: - View → ViewModel actions

enum ArmToolScreenViewAction {
    /// Arm the Tool (WHAT ⊥ WHEN) through the gate.
    case submit
    /// Turn the edited Tool off (after a confirmation).
    case turnOff
    /// User tapped the member selector row.
    case selectMembers
    /// User tapped the language selector row.
    case selectLanguage
}

// MARK: - Private helpers

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
