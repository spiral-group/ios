//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Agents tab step B): one wording for when a room tool runs
// and for whom, on every surface that lists tools.
//

import Compound
import SwiftUI

/// "Every message · for everyone". The kind decides the when: the server
/// pairs text tools with messages and call tools with calls.
nonisolated enum AgentToolTrigger {
    /// When a tool of `kind` runs; `nil` for a kind this build doesn't know.
    static func when(forKind kind: String) -> String? {
        switch kind {
        case "translate", "simplify", "correct", "rephrase", "summarize", "custom":
            UntranslatedL10n.screenAgentRoomToolTriggerMessages
        case "live_translate", "call_summary", "call_recording":
            UntranslatedL10n.screenAgentRoomToolTriggerCalls
        default:
            nil
        }
    }

    /// The whole line; the audience only when it is known and says something.
    static func line(forKind kind: String, audience: AudienceScope?) -> String? {
        join(when(forKind: kind), audience.flatMap(AgentToolAudience.text(for:)))
    }

    /// The line from the trigger the server reports. A trigger or audience
    /// this build doesn't know leaves its half out (decision 96).
    static func line(firing: AgentToolFiring?, audience: AudienceScope?, memberNames: [String: String]) -> String? {
        let when: String? = switch firing {
        case .onMessage: UntranslatedL10n.screenAgentRoomToolTriggerMessages
        case .onVoiceCall: UntranslatedL10n.screenAgentRoomToolTriggerCalls
        case nil: nil
        }
        return join(when, audience.flatMap { AgentToolAudience.text(for: $0, memberNames: memberNames) })
    }

    private static func join(_ parts: String?...) -> String? {
        let parts = parts.compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// THE audience wording ("for everyone", "only for me"…). The arm form's
/// choice and every tool row read it from here.
nonisolated enum AgentToolAudience {
    /// `nil` for a scope this build doesn't know (decision 96): no words
    /// rather than wrong ones.
    static func text(for scope: AudienceScope) -> String? {
        switch scope {
        case .anyone: UntranslatedL10n.screenAgentRoomToolAudienceAnyone
        case .nonSelfNonOwner: UntranslatedL10n.screenAgentRoomToolAudienceOthers
        case .ownerOnly: UntranslatedL10n.screenAgentRoomToolAudienceOwner
        case .specificSenders: UntranslatedL10n.screenAgentRoomToolAudienceSpecific
        case .everyoneExcept: UntranslatedL10n.screenAgentRoomToolAudienceExcept
        case .unknown: nil
        }
    }

    /// With the people a scope lists named, when every one of them has a
    /// name here; otherwise the scope's general words («для выбранных людей»).
    static func text(for scope: AudienceScope, memberNames: [String: String]) -> String? {
        let names = scope.members.compactMap { memberNames[$0] }
        guard !scope.members.isEmpty, names.count == scope.members.count else { return text(for: scope) }
        let list = names.joined(separator: ", ")
        switch scope {
        case .specificSenders: return UntranslatedL10n.screenAgentRoomToolAudienceSpecificNamed(list)
        case .everyoneExcept: return UntranslatedL10n.screenAgentRoomToolAudienceExceptNamed(list)
        default: return text(for: scope)
        }
    }
}

extension ToolDisplayName {
    /// Each tool kind's own icon; a newer kind gets a generic one.
    static func icon(forKind kind: String) -> KeyPath<CompoundIcons, Image> {
        switch kind {
        case "translate": \.translate
        case "simplify": \.textFormatting
        case "correct": \.checkCircle
        case "rephrase": \.edit
        case "summarize": \.listBulleted
        case "custom": \.compose
        case "live_translate": \.voiceCall
        case "call_summary": \.document
        case "call_recording": \.micOn
        default: \.extensions
        }
    }
}
