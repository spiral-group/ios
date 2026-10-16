//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063 Slice 4, ADR-0044 LT11 + ADR-0075 D7/D8 as
// revised 2026-09-02): personal listening is ONE switch — hear the
// translation the call produces, or the original voices only. It is made
// entirely in the client as a media-subscription selection; the backend
// never learns it and it is never persisted.
//
// What this file no longer is: a per-language picker. The two airing
// styles leave no per-listener language choice to make —
//
//   CONSECUTIVE  one shared `lt:<lang>` track per language, aired in turn
//                after the speaker pauses: a meeting with an interpreter.
//                EVERYONE hears EVERY configured language, the translated
//                speaker included (their own clip is the feedback that
//                stops them talking over it — ADR-0044 LT11). Personalising
//                it "would destroy the turn-taking premise" (ADR-0075 D8).
//   SIMULTANEOUS one language, per-speaker lanes `lt:<lang>:<speaker>`
//                aired over the ducked voice. The speaker never hears their
//                own lane (topology: the runtime unsubscribes it server-side
//                and this client refuses it too). One language — nothing to
//                pick.
//
// The iOS port had rendered a language radio for BOTH styles and enforced
// it by unsubscribing every other language's track — so a consecutive
// call configured ru+en played ONE of them, and a "smarter default"
// silenced the speaker's own clip that LT11 calls intentional. Both were
// symptoms of one thing: a picker running where no choice exists.
//
// Brief 0066 (ADR-0075 D7 amended 2026-09-04, revised 2026-09-06): in
// the simultaneous style a translated speaker's raw microphone is not
// unsubscribed; it stays subscribed and is ATTENUATED on this device
// (`RemoteAudioTrack.volume`) to `originalGain`. The rule is STATIC: a
// listener hears a speaker quietly for exactly as long as the listener
// receives that speaker's translation — from the moment a Live agent's
// document covers them, through every pause, until the coverage ends or
// the listener switches to the original voices. Nothing is metered (the
// per-utterance level gate of the first cut pumped the original on every
// gap and left it loud until the first sentence). The one exception is
// fail audible: a covered speaker talking with no lane of theirs airing,
// after one has aired here, is heard in full. Consecutive is untouched
// (ADR-0044 LT11: no surgery, no blend).

import Foundation

/// The participant's listening choice: the one switch every participant has.
nonisolated enum NativeCallListeningChoice: Hashable {
    /// Hear what the call produces — every translation lane, in whichever
    /// style. The default until first touch.
    case translation
    /// Original voices only: every translation track is unsubscribed.
    /// The one surviving personal option of ADR-0075 D7 — "I understand
    /// both languages, do not interpret for me" — valid in either style
    /// (ADR-0044 LT11's reserved `original: muted` amendment).
    case original
}

/// What the audio routing should play.
nonisolated enum NativeCallListeningChannel: Equatable {
    /// Subscribe to everything the policy allows: raw voices and every
    /// translation lane. Also the only legal state while the call produces
    /// no translation at all.
    case everything
    /// Original voices only, translations unsubscribed.
    case original
}

enum NativeCallListening {
    /// Every live-translation track carries this prefix, in BOTH airing
    /// styles. After it comes the BCP-47 language; a THIRD segment, when
    /// present, names the speaker whose voice this track replaces.
    ///
    ///   `lt:<language>`                 — consecutive: ONE shared track per
    ///                                     language, aired after the speaker
    ///                                     pauses. No speaker segment,
    ///                                     because it carries everyone.
    ///   `lt:<language>:<speakerMXID>`   — simultaneous: one lane per
    ///                                     speaker, aired over their voice.
    ///
    /// The speaker segment is what makes a lane a lane: it names whose
    /// voice the track replaces, which is what the lane memory (fail
    /// audible) is keyed on. Who is DUCKED is decided by the agent's
    /// document, not by track names — see `translatedSpeakers`.
    nonisolated static let translationTrackPrefix = "lt:"

    /// The playout gain of a covered speaker's raw microphone while this
    /// device hears their translation: a quiet bed that keeps the
    /// speaker's tone and pacing under the agent's voice. Not a setting.
    nonisolated static let originalGain: Float = 0.15

    /// Whether a track carries translation audio, in either airing style.
    nonisolated static func isTranslationTrack(trackName: String) -> Bool {
        trackName.hasPrefix(translationTrackPrefix)
    }

    /// The union of languages the call's agents currently produce,
    /// derived from published translation track names. Sorted for a
    /// stable display order — the Agent Center names them, nobody picks.
    nonisolated static func producedLanguages(trackNames: [String]) -> [String] {
        var languages = Set<String>()
        for name in trackNames {
            guard let language = translationLanguage(trackName: name) else { continue }
            languages.insert(language)
        }
        return languages.sorted()
    }

    /// The language a track carries, whichever style produced it, as a
    /// canonical base tag (`lt:en-US` and `lt:en-US:…` both → `en`).
    /// Nil for anything that is not translation audio. The agent's document
    /// is normalised the same way, so the two always compare like-for-like.
    nonisolated static func translationLanguage(trackName: String) -> String? {
        if trackName.hasPrefix(translationTrackPrefix) {
            let rest = trackName.dropFirst(translationTrackPrefix.count)
            let language = rest.prefix { $0 != ":" }
            guard !language.isEmpty else { return nil }
            return LanguageTag.base(of: String(language))
        }
        return nil
    }

    /// `lt:<language>:<speakerMXID>` → `<speakerMXID>`, nil for non-translation tracks.
    nonisolated static func translationSpeaker(trackName: String) -> String? {
        guard trackName.hasPrefix(translationTrackPrefix) else { return nil }
        let rest = trackName.dropFirst(translationTrackPrefix.count)
        guard let colon = rest.firstIndex(of: ":"), colon < rest.index(before: rest.endIndex) else { return nil }
        return String(rest[rest.index(after: colon)...])
    }

    /// Resolve the switch against what the call produces. With nothing
    /// produced there is nothing to refuse, so `original` collapses to
    /// `everything` — never a silence the user did not ask for.
    nonisolated static func channel(choice: NativeCallListeningChoice,
                                    producedLanguages: [String]) -> NativeCallListeningChannel {
        guard !producedLanguages.isEmpty else { return .everything }
        switch choice {
        case .translation: return .everything
        case .original: return .original
        }
    }

    /// Who a listener hears in translation, from the agents' documents
    /// (Brief 0066 rev. 2): every speaker among `speakers` that a LIVE,
    /// Live-style (simultaneous) agent's active booth covers, with the
    /// language it is heard in. The document reaches every device the
    /// instant the agent is configured, so this is true BEFORE the first
    /// lane is published — which is exactly when the original must already
    /// be quiet. An Interpreter (consecutive) claim covers nobody here:
    /// its rendering airs after the speaker stops (ADR-0044 LT11). A claim
    /// with no style reads as Live, the wire default (ADR-0044 LT9).
    ///
    /// Two agents covering one speaker: the smallest language tag wins,
    /// deterministically, so the roster label never flips between
    /// derivations with dictionary order.
    nonisolated static func translatedSpeakers(speakers: some Sequence<String>,
                                               claims: some Sequence<SpiralAgentStateReader.AgentClaim>) -> [String: String] {
        let liveBooths = claims
            .filter { $0.lifecycle == .live && $0.translation.style != .consecutive }
            .flatMap(\.translation.activeBooths)
        var translated: [String: String] = [:]
        for speaker in speakers {
            for booth in liveBooths where booth.coverage.covers(speaker) {
                guard let language = booth.targetLanguages.min() else { continue }
                if let existing = translated[speaker], existing <= language { continue }
                translated[speaker] = language
            }
        }
        return translated
    }

    /// The subscription policy for one track. A raw microphone is NEVER
    /// excluded by listening any more (Brief 0066): a translated speaker's
    /// mic stays subscribed and is ducked on the device — the plan's
    /// `originalDucking` names whom. Only the self-lane rule and the
    /// `original` channel refuse tracks here.
    nonisolated static func isTrackExcluded(trackName: String,
                                            channel: NativeCallListeningChannel,
                                            ownUserID: String) -> Bool {
        // The self-exclusion contract binds every subscriber in every
        // channel: a speaker never hears their own SIMULTANEOUS lane. It is
        // a property of that topology only — a consecutive `lt:<lang>`
        // track is shared and, by ADR-0044 LT11, the speaker's own clip on
        // it is meant to be heard.
        if trackName.hasPrefix(translationTrackPrefix), trackName.hasSuffix(":\(ownUserID)") {
            return true
        }
        switch channel {
        case .original:
            return isTranslationTrack(trackName: trackName)
        case .everything:
            return false
        }
    }
}
