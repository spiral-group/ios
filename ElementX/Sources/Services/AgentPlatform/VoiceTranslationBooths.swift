//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0062 parity, backend ADR-0075): pure helpers
// over the translation BOOTH model — who is translated → into which
// languages. Ported from `element-call/src/spiral/sheet/booths.ts` so
// the native editor enforces exactly the rules the web widget does.
//
// Load-bearing history: the pre-0062 web editor projected the booth
// list onto ONE flat audience+language pair, so an owner who had
// configured "translate only me" widened the translation to everyone
// just by changing a language, and a second booth's members were
// silently erased on every Apply. The first native Agent Center
// repeated that mistake (single `anyone` booth per write, operator
// report 2026-08-19); this module exists so it cannot happen again —
// the editor edits the FULL booth list, never a projection of it.

import Foundation

/// The speaker scopes a booth can carry on the wire.
nonisolated enum VoiceSpeakerScope: String {
    case anyone
    case nonSelfNonOwner = "non_self_non_owner"
    case ownerOnly = "owner_only"
    case specificSenders = "specific_senders"
    /// Created ONLY by displacement narrowing (ADR-0075 D4), never by
    /// hand: the editor renders it read-only and offers switching AWAY.
    case everyoneExcept = "everyone_except"

    /// The scopes the editor offers directly.
    static let editable: [VoiceSpeakerScope] = [.anyone, .nonSelfNonOwner, .ownerOnly, .specificSenders]
}

nonisolated extension VoiceTranslationBooth {
    var scope: VoiceSpeakerScope? {
        VoiceSpeakerScope(rawValue: speakerScope)
    }
}

nonisolated enum VoiceTranslationBooths {
    /// The one-`anyone`-booth degenerate case the simple sentence
    /// renders: "translate everyone into [language]".
    static func reducesToSimple(_ booths: [VoiceTranslationBooth]) -> Bool {
        if booths.isEmpty { return true }
        return booths.count == 1
            && booths[0].scope == .anyone
            && booths[0].targetLanguages.count == 1
    }

    /// A booth list every field of which is filled in enough to submit.
    static func isValid(_ booths: [VoiceTranslationBooth]) -> Bool {
        !booths.isEmpty && booths.allSatisfy { booth in
            !booth.targetLanguages.isEmpty
                && (booth.scope != .specificSenders || !booth.speakerMembers.isEmpty)
        }
    }

    /// The device-locale language, when the catalog offers it (D6: the
    /// simple tier pre-selects it so "translate everyone into X" is one
    /// decision, not two).
    static func localeSeed(catalog: [VoiceControlsCatalogLanguage],
                           locale: String = Locale.current.identifier) -> String? {
        let base = LanguageTag.base(of: locale)
        return catalog.first { $0.code == base }?.code
    }

    // MARK: - Displacement detection (Brief 0062 W5 / ADR-0075 D4)

    /// A coverage summary comparable across snapshots.
    struct Coverage: Equatable {
        var broad = false
        var excluded = Set<String>()
        var members = Set<String>()
        var ownVoice = false
    }

    static func summarize(_ booths: [VoiceTranslationBooth]) -> Coverage {
        var coverage = Coverage()
        for booth in booths {
            switch booth.scope {
            case .anyone, .nonSelfNonOwner:
                coverage.broad = true
            case .everyoneExcept:
                coverage.excluded.formUnion(booth.speakerMembers)
            case .specificSenders:
                coverage.members.formUnion(booth.speakerMembers)
            case .ownerOnly:
                coverage.ownVoice = true
            case nil:
                break
            }
        }
        return coverage
    }

    /// Did the coverage strictly SHRINK between two state emissions?
    /// Displacement only ever narrows: a broad booth becomes
    /// `everyone_except`, an exclusion list grows, a member list loses
    /// someone, or a booth disappears — so a shrink the owner did not
    /// write themself is the displaced-owner signal.
    static func coverageShrank(previous: [VoiceTranslationBooth],
                               next: [VoiceTranslationBooth]) -> Bool {
        guard !previous.isEmpty else { return false }
        let before = summarize(previous)
        let after = summarize(next)
        if before.broad, !after.broad { return true }
        if before.broad, after.broad, after.excluded.count > before.excluded.count { return true }
        if before.ownVoice, !after.ownVoice { return true }
        for member in before.members {
            if !after.members.contains(member), !after.broad { return true }
            if after.excluded.contains(member) { return true }
        }
        return false
    }
}
