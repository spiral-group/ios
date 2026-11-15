//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383, the operator's pick B of `DESIGNS/0083-call-motion/pill-audit.md`): what the
// agent pill says. At rest it says only whose agent is in the call; when the agent does something for the people in it
// (listens, translates, takes notes, failed to deliver, leaves) it says that instead, in one line, with at most one
// glyph chip. It never says what the screen already shows: speaking is the Halo's, recording is the header's REC, and
// connecting or on hold is the header's status.

import Foundation

struct NativeCallAgentPillContent: Equatable {
    /// What the round slot at the leading end holds.
    enum Slot: Equatable {
        /// The agent's avatar, its Halo bending with its voice; dimmed while it leaves.
        case avatar(isDimmed: Bool)
        case failure
        case paused
    }

    /// The one glyph beside the line, never a second surface.
    enum Chip: Equatable {
        case listening
        /// At most two language codes; `more` counts the rest.
        case translation(codes: [String], more: Int)
        case originalVoice
        case notes
    }

    let slot: Slot
    let line: String
    /// The line in the critical ink (a delivery failed), never by colour alone: the slot carries the glyph too.
    let isCritical: Bool
    let chip: Chip?
    /// The name always, then what it does in words, then how many other agents are here.
    let accessibilityLabel: String

    init(_ state: NativeCallAgentBlockState) {
        let identity = state.isOwn ? UntranslatedL10n.screenNativeCallAgentPillYourAssistant : NativeCallAssistantTitle(displayName: state.name).name
        let function = Self.function(state)

        slot = function.slot
        line = function.line ?? identity
        isCritical = function.isCritical
        chip = function.chip

        let spoken = if let languages = function.spokenLanguages {
            UntranslatedL10n.a11yNativeCallAgentBlockAiring(identity, NativeCallAgentStatusCopy.spokenLanguages(languages))
        } else if let words = function.spoken {
            UntranslatedL10n.a11yNativeCallAgentBlockRole(identity, words)
        } else {
            UntranslatedL10n.a11yNativeCallAgentPillInCall(identity)
        }
        accessibilityLabel = state.otherAgentCount > 0
            ? UntranslatedL10n.a11yNativeCallAgentPillOtherAgents(spoken, state.otherAgentCount)
            : spoken
    }

    /// A language as the chip shows it: its code in capitals, except Ukrainian, whose code `UK` reads as the United
    /// Kingdom; the country's `UA` is what people read as Ukrainian.
    static func code(_ language: String) -> String {
        let base = Locale.Language(identifier: language).languageCode?.identifier ?? language
        return base == "uk" ? "UA" : base.uppercased()
    }

    // MARK: - Private

    private struct Function {
        var slot = Slot.avatar(isDimmed: false)
        /// Nil: the line is who the agent is.
        var line: String?
        var isCritical = false
        var chip: Chip?
        /// What VoiceOver says after the name; nil says it is in the call.
        var spoken: String?
        /// Translating: VoiceOver names every language in full, with the verb.
        var spokenLanguages: [String]?
    }

    /// Priority: on its way while the call rings, leaving, failure, translation, listening, notes, then who it is.
    private static func function(_ state: NativeCallAgentBlockState) -> Function {
        if state.joinsWhenAnswered {
            let line = UntranslatedL10n.screenNativeCallAssistantsJoinsWhenAnswered
            return Function(slot: .avatar(isDimmed: true), line: line, spoken: line)
        }
        if state.isLeaving {
            let leaving = UntranslatedL10n.screenNativeCallAgentCenterLeaving
            return Function(slot: .avatar(isDimmed: true), line: leaving, spoken: leaving)
        }

        switch state.event {
        case .failure:
            let line = state.failedDelivery == .summary
                ? UntranslatedL10n.screenNativeCallAgentPillSummaryNotSent
                : UntranslatedL10n.screenNativeCallAgentPillRecordingNotSaved
            return Function(slot: .failure, line: line, isCritical: true, spoken: line)
        case .airing(.translation(let languages)), .idle(nil, let languages) where !languages.isEmpty:
            return translating(languages)
        case .paused:
            let line = UntranslatedL10n.screenNativeCallAgentPillTranslationPaused
            return Function(slot: .paused, line: line, spoken: line)
        case .original:
            let line = UntranslatedL10n.screenNativeCallAgentPillOriginalVoice
            return Function(line: line, chip: .originalVoice, spoken: line)
        case .idle(.conversation, _):
            let line = UntranslatedL10n.screenNativeCallAgentPillListening
            return Function(line: line, chip: .listening, spoken: line)
        case .airing(.conversation), .idle:
            // Speaking is the Halo's; recording the header's REC; waiting the header's status. A summary armed under a
            // recording still shows: notes have no other mark on screen.
            guard state.isTakingNotes else { return Function() }
            let line = UntranslatedL10n.screenNativeCallAgentPillTakingNotes
            return Function(line: line, chip: .notes, spoken: line)
        }
    }

    private static func translating(_ languages: [String]) -> Function {
        Function(line: UntranslatedL10n.screenNativeCallAgentPillTranslating,
                 chip: .translation(codes: languages.prefix(2).map(code), more: max(0, languages.count - 2)),
                 spokenLanguages: languages)
    }
}
