//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359): the room tools a person can turn on, and one of their own as the screens
// use it. Every chat-tools screen reads a kind's name, line and icon from here.
//

import Compound
import SwiftUI

/// A tool kind this build knows, by the backend's `ToolParams.kind`.
nonisolated enum AgentToolKind: String, CaseIterable, Identifiable, Equatable {
    case translate
    case simplify
    case correct
    case rephrase
    case summarize
    case custom
    case liveTranslate = "live_translate"
    case callSummary = "call_summary"
    case callRecording = "call_recording"

    var id: String {
        rawValue
    }

    /// The call tools; the others act on messages.
    var firesOnCalls: Bool {
        switch self {
        case .liveTranslate, .callSummary, .callRecording: true
        default: false
        }
    }

    var needsLanguage: Bool {
        self == .translate || self == .liveTranslate
    }

    var needsInstruction: Bool {
        self == .rephrase || self == .custom
    }

    var title: String {
        switch self {
        case .translate: UntranslatedL10n.screenArmToolKindTranslate
        case .simplify: UntranslatedL10n.screenArmToolKindSimplify
        case .correct: UntranslatedL10n.screenArmToolKindCorrect
        case .rephrase: UntranslatedL10n.screenArmToolKindRephrase
        case .summarize: UntranslatedL10n.screenArmToolKindSummarize
        case .custom: UntranslatedL10n.screenArmToolKindCustom
        case .liveTranslate: UntranslatedL10n.screenArmToolLiveCallTitle
        case .callSummary: UntranslatedL10n.screenArmToolCallSummaryTitle
        case .callRecording: UntranslatedL10n.screenArmToolCallRecordingTitle
        }
    }

    /// One line on what it does.
    var explanation: String {
        switch self {
        case .translate: UntranslatedL10n.screenAddToolTranslateSubtitle
        case .simplify: UntranslatedL10n.screenAddToolSimplifySubtitle
        case .correct: UntranslatedL10n.screenAddToolCorrectSubtitle
        case .rephrase: UntranslatedL10n.screenAddToolRephraseSubtitle
        case .summarize: UntranslatedL10n.screenAddToolSummarizeSubtitle
        case .custom: UntranslatedL10n.screenAddToolCustomSubtitle
        case .liveTranslate: UntranslatedL10n.screenAgentCapabilitiesLiveCallSubtitle
        case .callSummary: UntranslatedL10n.screenAgentCapabilitiesCallSummarySubtitle
        case .callRecording: UntranslatedL10n.screenAgentCapabilitiesCallRecordingSubtitle
        }
    }

    var icon: KeyPath<CompoundIcons, Image> {
        ToolDisplayName.icon(forKind: rawValue)
    }

    /// The kinds `available_tool_kinds` names, in this order. A kind newer than this build is left out (decision 96).
    static func offered(availableToolKinds: [String]) -> [AgentToolKind] {
        let available = Set(availableToolKinds)
        return allCases.filter { available.contains($0.rawValue) }
    }
}

/// A tool's name by the backend's `kind`, for the surfaces that show every kind in a few words: the banner and the
/// timeline's state row. Translate kinds give the base name; a caller with a language composes its own line.
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

    /// The name with the language when the safe slice carries one, as every tool row and the read-only page say it.
    static func title(forKind kind: String, language: String?) -> String {
        if kind == "translate" || kind == "live_translate", let language {
            return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
        }
        return name(forKind: kind)
    }
}

/// One of the person's own tools: what its form opens from. It needs the id, the params and the trigger, which only an
/// owner's read carries, so a tool of the safe slice can't become one.
struct ActiveToolDetail: Equatable, Identifiable {
    let toolID: String
    /// `nil` for a kind newer than this build: it can only be turned off.
    let kind: AgentToolKind?
    let params: ToolParams
    let trigger: TriggerKind
    /// "Translate → English".
    let title: String
    /// "Every message · for everyone".
    let subtitle: String
    /// Whether the catalogue says this tool's kind can fire for this agent here. The server may still list one that
    /// can't (decision 168: a company agent's call tool); it is shown as not available, never armed.
    var canFire = true

    var id: String {
        toolID
    }

    /// An edit replaces the tool, so one whose kind, trigger or scope this build does not know (a newer platform's,
    /// decision 96) is not edited here: the form would write what the person never saw.
    var isEditable: Bool {
        guard kind != nil else { return false }
        switch trigger {
        case .unknown:
            return false
        case .onMessage(let scope), .onVoiceCall(let scope):
            if case .unknown = scope { return false } else { return true }
        }
    }

    init?(_ tool: RoomToolView) {
        guard let toolID = tool.toolID, let params = tool.params, let trigger = tool.trigger else { return nil }
        self.toolID = toolID
        kind = AgentToolKind(rawValue: tool.toolKind)
        self.params = params
        self.trigger = trigger
        title = Self.title(for: params)
        subtitle = Self.subtitle(for: trigger, kind: params.kind)
    }

    /// The caller's own tools of an agent in a room's read.
    static func tools(in roomTools: RoomToolsView, ownAgentID: String) -> [ActiveToolDetail] {
        roomTools.agents.first { $0.agentID == ownAgentID }?.tools.compactMap(ActiveToolDetail.init) ?? []
    }

    private static func title(for params: ToolParams) -> String {
        switch params {
        case .translate(let language):
            return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
        case .simplify:
            return UntranslatedL10n.screenArmToolKindSimplify
        case .correct:
            return UntranslatedL10n.screenArmToolKindCorrect
        case .rephrase(let instruction):
            return UntranslatedL10n.screenAgentToolsListTitleRephrase(instruction)
        case .summarize:
            return UntranslatedL10n.screenArmToolKindSummarize
        case .custom:
            return UntranslatedL10n.screenArmToolKindCustom
        case .liveTranslate(let language):
            return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
        case .callSummary:
            return UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle
        case .callRecording:
            return UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle
        case .unknown:
            return UntranslatedL10n.screenAgentToolsListTitleUnknown
        }
    }

    /// When it runs and for whom, in the words every tool row uses.
    private static func subtitle(for trigger: TriggerKind, kind: String) -> String {
        switch trigger {
        case .onMessage(let scope), .onVoiceCall(let scope):
            // A scope newer than this build: the row says to update, as an edit would.
            if case .unknown = scope { return UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle }
            return AgentToolTrigger.line(forKind: kind, audience: scope) ?? UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle
        case .unknown:
            return UntranslatedL10n.screenAgentToolsListNeedsUpdateTitle
        }
    }
}
