//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM: Agent Platform feature (Brief 0036 / ADR-0048).
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.
// The "what can this agent do in this room" sheet —
// reached from the composer "+" Agent section. Reads the unified Tool +
// Trigger state (`GET /rooms/:room_id/tools`) and lists each capability
// with its live on/off state, projected from the caller's own agent
// entry; a tap opens the arm form (a Tool ⊥ Trigger the owner arms
// through the three-layer gate).
//
// This replaces the Brief 0034 `/controls`-shaped stub: schedule +
// memory are chat-only now (no REST surface), so only the two room-scoped
// tool families survive here — standing text transforms (`on_message`)
// and voice live-translation (`on_voice_call`).
//

import Compound
import Foundation
import SwiftUI

// MARK: - ViewModel → Coordinator actions

enum AgentCapabilitiesScreenViewModelAction {
    /// User tapped a capability row — the coordinator presents the arm
    /// form, seeding it with any active Tool so the form can offer
    /// "manage / turn off" rather than a fresh "add".
    case selectCapability(AgentCapability, active: ActiveCapabilityTool?)
    /// User dismissed the sheet.
    case dismiss
}

// MARK: - Domain

/// The capabilities this UI exposes, one per room-scoped Tool family the
/// backend accepts (ADR-0048). Adding a capability here + an arm-form
/// branch is the only work to surface a new tool family.
///
/// `translateMessages` maps to the text transforms armed with an
/// `on_message` trigger; `liveCallTranslation` maps to the
/// `live_translate` tool armed with an `on_voice_call` trigger. Schedule
/// + memory are deliberately absent (chat-only, no `/tools` surface).
enum AgentCapability: String, CaseIterable, Identifiable, Equatable {
    case translateMessages
    case liveCallTranslation
    case callSummary
    case callRecording

    var id: String {
        rawValue
    }

    /// The backend `ToolParams.kind`s that project onto this capability.
    /// A read-model tool whose `toolKind` is in this set counts as this
    /// capability being "on".
    var toolKinds: Set<String> {
        switch self {
        case .translateMessages:
            // All the standing text transforms live under this row.
            return ["translate", "simplify", "correct", "rephrase", "summarize", "custom"]
        case .liveCallTranslation:
            return ["live_translate"]
        case .callSummary:
            return ["call_summary"]
        case .callRecording:
            return ["call_recording"]
        }
    }

    /// The Compound icon for this capability. Single source of truth shared by
    /// the capabilities sheet AND the all-participant tools banner (Brief 0044)
    /// so the two surfaces never drift.
    var icon: KeyPath<CompoundIcons, Image> {
        switch self {
        case .translateMessages: return \.translate
        case .liveCallTranslation: return \.voiceCall
        case .callSummary: return \.document
        case .callRecording: return \.micOn
        }
    }

    /// The capability a backend `toolKind` projects onto, or `nil` for an
    /// unknown kind.
    static func capability(forToolKind kind: String) -> AgentCapability? {
        allCases.first { $0.toolKinds.contains(kind) }
    }

    /// The capabilities with a tool kind in the catalog's
    /// `available_tool_kinds`, in display order.
    static func offered(availableToolKinds: [String]) -> [AgentCapability] {
        let available = Set(availableToolKinds)
        return allCases.filter { !$0.toolKinds.isDisjoint(with: available) }
    }

    /// The icon to show for a single active tool of the given `toolKind`,
    /// resolved via its capability. Falls back to the translate icon for an
    /// unknown kind so a banner row always renders something.
    static func icon(forToolKind kind: String) -> KeyPath<CompoundIcons, Image> {
        capability(forToolKind: kind)?.icon ?? \.translate
    }
}

/// Localized display names for a tool by its backend `kind`, shared by the
/// all-participant tools banner and the timeline state-event row (Brief 0044).
/// Covers EVERY kind — including the call-artifact kinds (`call_summary` /
/// `call_recording`) that aren't in `ArmToolKind` — so those surfaces never
/// fall back to the raw, unlocalized kind (e.g. "Call_summary"). Translate
/// kinds return their base name here; callers that have a target language
/// compose the "Translating to X" line themselves.
nonisolated enum ToolDisplayName {
    static func name(forKind kind: String) -> String {
        switch kind {
        case "translate", "live_translate":
            return UntranslatedL10n.screenArmToolKindTranslate
        case "simplify":
            return UntranslatedL10n.screenArmToolKindSimplify
        case "correct":
            return UntranslatedL10n.screenArmToolKindCorrect
        case "rephrase":
            return UntranslatedL10n.screenArmToolKindRephrase
        case "summarize":
            return UntranslatedL10n.screenArmToolKindSummarize
        case "custom":
            return UntranslatedL10n.screenArmToolKindCustom
        case "call_summary":
            return UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle
        case "call_recording":
            return UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle
        default:
            // A kind newer than this build: a generic word, never the raw tag.
            return UntranslatedL10n.screenAgentToolsListTitleUnknown
        }
    }
}

/// A capability's currently-active Tool(s), if any, projected from the
/// caller's own agent entry in `GET /rooms/:room_id/tools`. Carries the
/// tool id(s) the manage/turn-off form needs. `count` drives the
/// "· N active" style subtitle.
struct ActiveCapabilityTool: Equatable {
    /// Backend tool ids backing this active capability (a capability can
    /// have more than one armed tool — e.g. two translate directions).
    let toolIDs: [String]
    /// A short human summary line rendered under the capability title
    /// (e.g. "Translating to English").
    let summary: String
    let count: Int
}

// MARK: - View ↔ ViewModel state

enum AgentCapabilitiesListState: Equatable {
    /// `GET /rooms/:room_id/tools` in flight.
    case loading
    /// Resolved. `active[capability]` is non-nil when that capability
    /// has ≥1 active Tool for the caller's own agent in the room.
    case loaded(active: [AgentCapability: ActiveCapabilityTool])
    /// The fetch failed. Inline retry.
    case failed
}

struct AgentCapabilitiesScreenViewState: BindableState {
    /// Display name of the agent whose capabilities these are.
    let agentDisplayName: String
    let showsDoneButton: Bool
    var listState: AgentCapabilitiesListState = .loading
    /// The rows the loaded list shows: what can fire for this agent in this
    /// room (the catalog's kinds), plus every capability with an active tool,
    /// so the owner can always turn one off. A text tool in the owner DM, call
    /// translation in a 1:1 room or a call tool for a company agent (decision
    /// 168) would be refused, so they are not offered unless one is already on.
    var offeredCapabilities: [AgentCapability] = []
    /// The offered capabilities the catalog says can fire. An active tool
    /// outside it is listed by the server but never runs: its row says so
    /// instead of "On".
    var firingCapabilities: [AgentCapability] = []
    var bindings: AgentCapabilitiesScreenViewStateBindings

    /// The active Tool for a capability, or nil.
    func activeTool(for capability: AgentCapability) -> ActiveCapabilityTool? {
        if case .loaded(let active) = listState { return active[capability] }
        return nil
    }

    /// On, but it can't fire here (decision 168: a company agent's old call
    /// tool), so the row offers only turning it off.
    func isUnavailable(_ capability: AgentCapability) -> Bool {
        activeTool(for: capability) != nil && !firingCapabilities.contains(capability)
    }

    var isFailed: Bool {
        if case .failed = listState { return true }
        return false
    }
}

struct AgentCapabilitiesScreenViewStateBindings {
    var alertInfo: AlertInfo<AgentCapabilitiesScreenAlertType>?
}

enum AgentCapabilitiesScreenAlertType: Hashable {
    case loadFailed
    /// An active tool that can't fire here: the only offer is turning it off.
    case unavailable
    case turnOffFailed
}

// MARK: - View → ViewModel actions

enum AgentCapabilitiesScreenViewAction {
    /// `.onAppear` — fetch the current tool state.
    case appeared
    /// Retry after a failed fetch.
    case retry
    /// User tapped a capability row.
    case selectCapability(AgentCapability)
    /// User tapped Done.
    case done
}
