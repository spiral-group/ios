//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// The arm form reached from a capability row in
// `AgentCapabilitiesScreen`. It composes a typed Tool (the WHAT —
// `ToolParams`) with a typed Trigger (the WHEN — `TriggerKind`) and arms
// it through the three-layer gate via `POST …/tools` (`tool.arm`), or
// turns the capability off via `DELETE …/tools/:id` (`tool.disable`).
//
// The form is typed rather than raw-JSON-schema-driven: the catalog
// (`GET …/tools/catalog`) confirms the field set + bounds (instruction
// 2..2000 chars, members 1..64) but the ViewModel builds the same
// `ToolParams` / `TriggerKind` / `AudienceScope` enums the read model +
// service already use (`RoomToolsModels.swift`). Semantic fields the
// schema can't express — a language input, an MXID member selection —
// are layered on top.
//

import Foundation

// MARK: - ViewModel → Coordinator actions

enum ArmToolScreenViewModelAction {
    /// The arm (or disable) applied through the gate — the coordinator
    /// dismisses the sheet and asks the capabilities screen to refresh.
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

/// The transform kinds the arm form offers for the "Translate messages"
/// capability. `liveCallTranslation` uses a fixed `live_translate` tool,
/// so it isn't in this picker.
enum ArmToolKind: String, CaseIterable, Identifiable, Equatable {
    case translate
    case simplify
    case correct
    case rephrase
    case summarize
    case custom

    var id: String {
        rawValue
    }

    /// Whether this kind needs the free-text language field.
    var needsLanguage: Bool {
        self == .translate
    }

    /// Whether this kind needs the free-text instruction field.
    var needsInstruction: Bool {
        self == .rephrase || self == .custom
    }

    /// Human name for this kind, reused by the arm-tool picker and the
    /// all-participant tools banner (Brief 0044) so the two surfaces
    /// never drift.
    var bannerTitle: String {
        switch self {
        case .translate: UntranslatedL10n.screenArmToolKindTranslate
        case .simplify: UntranslatedL10n.screenArmToolKindSimplify
        case .correct: UntranslatedL10n.screenArmToolKindCorrect
        case .rephrase: UntranslatedL10n.screenArmToolKindRephrase
        case .summarize: UntranslatedL10n.screenArmToolKindSummarize
        case .custom: UntranslatedL10n.screenArmToolKindCustom
        }
    }
}

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

/// The single row the parameters section shows for a text transform. Every
/// kind has exactly one, so picking a kind never moves the rows below it —
/// a kind without a language used to drop the section and slide the bulk
/// "Turn off" under the finger (re-walk R5).
enum ArmToolParamsRow: Equatable {
    case language
    case instruction
    case nothingToSet
}

// MARK: - View ↔ ViewModel state

struct ArmToolScreenViewState: BindableState {
    let capability: AgentCapability
    /// Non-nil when the capability already has an active Tool — the form
    /// renders a "Turn off" affordance in addition to arming a new one.
    let activeToolIDs: [String]
    /// The localized display name for a stored canonical code.
    func displayName(forLanguageCode code: String) -> String {
        TranslationLanguageDisplayName.localizedName(for: code)
    }

    /// True when editing an existing tool (title "Edit" + "Save"; submit is
    /// one arm that replaces it). False when creating a new tool.
    let isEditing: Bool
    /// Display name of the agent being armed (rendered in the footer).
    let agentDisplayName: String
    var bindings: ArmToolScreenViewStateBindings

    /// The scope needs members but none are selected yet → submit blocked.
    var isMissingMembers: Bool {
        showsScopeSelector && bindings.scope.requiresMembers && bindings.members.isEmpty
    }

    /// A free-text field is required but empty/too short → submit blocked.
    var isMissingRequiredText: Bool {
        if capability == .liveCallTranslation {
            return bindings.targetLanguages.isEmpty
        }
        guard capability == .translateMessages else {
            return false
        }
        if bindings.kind.needsLanguage {
            return bindings.language.trimmed.isEmpty
        }
        if bindings.kind.needsInstruction {
            return bindings.instruction.trimmed.count < 2
        }
        return false
    }

    var canSubmit: Bool {
        !isMissingMembers && !isMissingRequiredText && !isSubmitting
    }

    var isSubmitting = false
    var hasActiveTool: Bool {
        !activeToolIDs.isEmpty
    }

    var isLiveTranslation: Bool {
        capability == .liveCallTranslation
    }

    var showsKindPicker: Bool {
        capability == .translateMessages
    }

    var showsScopeSelector: Bool {
        capability == .translateMessages || capability == .liveCallTranslation
    }

    /// `nil` unless this is a text transform.
    var textParamsRow: ArmToolParamsRow? {
        guard capability == .translateMessages else { return nil }
        if bindings.kind.needsLanguage { return .language }
        if bindings.kind.needsInstruction { return .instruction }
        return .nothingToSet
    }
}

struct ArmToolScreenViewStateBindings {
    /// Selected transform kind (ignored when `isLiveTranslation`).
    var kind: ArmToolKind = .translate
    /// Target language (used by `translate` + `live_translate`).
    var language = ""
    /// Ordered target languages used by `live_translate`.
    var targetLanguages: [String] = []
    /// Free-text instruction (used by `rephrase` + `custom`).
    var instruction = ""
    /// Live-translation presentation style.
    var liveStyle: LiveTranslationStyle = .simultaneous
    /// Audience scope for the trigger.
    var scope: ArmToolScope = .anyone
    /// Concrete MXIDs for a member-carrying scope.
    var members: [String] = []

    var alertInfo: AlertInfo<ArmToolScreenAlertType>?
}

enum ArmToolScreenAlertType: Hashable {
    case armFailed
    case disableFailed
    /// The bulk "Turn off" asks first: one tap turns the room's tools of
    /// this kind off for everyone.
    case confirmTurnOff
}

// MARK: - View → ViewModel actions

enum ArmToolScreenViewAction {
    /// Arm the Tool (WHAT ⊥ WHEN) through the gate.
    case submit
    /// Turn off every active Tool for this capability (after a confirmation).
    case turnOff
    /// User tapped the member selector row.
    case selectMembers
    /// User tapped the language selector row.
    case selectLanguage(index: Int?)
    case removeLanguage(index: Int)
    case moveLanguages(fromOffsets: IndexSet, toOffset: Int)
}

// MARK: - Private helpers

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
