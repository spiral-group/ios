//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063 Slice 4, Brief 0085): personal listening is a
// language choice over the Live lanes that exist (`lt:<lang>:<speaker>`), or
// the original voices — the default (question 403, model point 1). It is made
// entirely in the client as a media-subscription selection and never
// persisted; the backend learns only the language a person publishes as
// theirs with their call membership (ADR-0094 A.1, D10).
//
// Consecutive (`lt:<lang>`, one shared track per language, aired after the
// speaker pauses) survives only as the pocket interpreter in a private call
// with one's own assistant (ADR-0044 as amended): communal by LT11, so it is
// never unsubscribed and has no language to pick.
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
// after one has aired here, is heard in full. And one release (operator,
// 2026-11-12): a covered speaker none of whose lanes into your language
// has aired here after 4 s of their own speech in this coverage is heard
// in full too — their declared language is wrong and the model stays
// silent, so ducking them would leave nothing in their place. It counts
// speech, not wall time, says nothing on screen (not a falter), holds
// until a lane of theirs airs (then ducking and the falter rule as
// before), and starts from zero when the coverage starts anew
// (`NativeCallUnairedCoverage`). Consecutive is untouched (ADR-0044 LT11:
// no surgery, no blend).

import Foundation

/// The participant's listening choice (Brief 0085, question 403, model point 1): the language they hear the call in,
/// over the lanes that exist, or the original voices — the default. Client-only (ADR-0075 D7 as amended by ADR-0094).
nonisolated enum NativeCallListeningChoice: Hashable {
    case original
    /// A catalog code in its exact form: the Live lanes into it, over their speakers' ducked voices.
    case language(String)

    var language: String? {
        if case .language(let language) = self { return language }
        return nil
    }
}

/// What the audio routing should play.
nonisolated enum NativeCallListeningChannel: Equatable {
    /// Original voices: no Live lane is subscribed. The pocket interpreter's shared consecutive track still plays — the
    /// owner set it up for themself (ADR-0044 as amended: consecutive only in the private call).
    case original
    /// The Live lanes into this language, and the original of every speaker no lane covers.
    case translation(language: String)

    var language: String? {
        if case .translation(let language) = self { return language }
        return nil
    }
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

    /// Reserved by ADR-0094 D12 for the owner's phone audio (`ltd:<lang>:<speaker>`), a later release: this build
    /// subscribes none of them, in any channel — never as a raw microphone either.
    nonisolated static let reservedTranslationTrackPrefix = "ltd:"

    /// Whether a track carries translation audio, in either airing style, or the reserved `ltd:` form.
    nonisolated static func isTranslationTrack(trackName: String) -> Bool {
        trackName.hasPrefix(translationTrackPrefix) || trackName.hasPrefix(reservedTranslationTrackPrefix)
    }

    /// Whether `claim`, the publisher's own document, lists the lane a track carries (ADR-0094 A.6): an
    /// `lt:<lang>:<speaker>` lane by `(speaker, voice, lang)`, the pocket interpreter's shared `lt:<lang>` by the
    /// language it airs. Nothing without a document, or while its translation doesn't air.
    nonisolated static func isListed(trackName: String, in claim: SpiralAgentStateReader.TranslationClaim?) -> Bool {
        guard let claim, claim.isActive, let language = translationLanguage(trackName: trackName) else { return false }
        guard let speaker = translationSpeaker(trackName: trackName) else {
            return claim.producedLanguages.contains(language)
        }
        return claim.lanes.contains(VoiceTranslationLane(speaker: speaker, input: .voice, language: language))
    }

    /// The language a track carries, whichever style produced it: the catalog code exactly as the name spells it
    /// (`lt:pt-BR:…` → `pt-BR`), the same form the agent's document uses (ADR-0094 A.6). Nil for anything that is
    /// not translation audio.
    nonisolated static func translationLanguage(trackName: String) -> String? {
        guard trackName.hasPrefix(translationTrackPrefix) else { return nil }
        let language = trackName.dropFirst(translationTrackPrefix.count).prefix { $0 != ":" }
        return language.isEmpty ? nil : String(language)
    }

    /// `lt:<language>:<speakerMXID>` → `<speakerMXID>`, nil for non-translation tracks.
    nonisolated static func translationSpeaker(trackName: String) -> String? {
        guard trackName.hasPrefix(translationTrackPrefix) else { return nil }
        let rest = trackName.dropFirst(translationTrackPrefix.count)
        guard let colon = rest.firstIndex(of: ":"), colon < rest.index(before: rest.endIndex) else { return nil }
        return String(rest[rest.index(after: colon)...])
    }

    /// Resolve the choice against what the call produces: a language nobody produces is heard as the original, never
    /// as a silence the user did not ask for.
    nonisolated static func channel(choice: NativeCallListeningChoice,
                                    producedLanguages: [String]) -> NativeCallListeningChannel {
        guard let language = choice.language, producedLanguages.contains(language) else { return .original }
        return .translation(language: language)
    }

    /// Who a listener hears in translation, from the agents' documents (ADR-0094 D5, D10): every speaker among
    /// `speakers` with a lane into `language` that a live agent airs in the Live style, with that language. The
    /// document names its lanes as soon as the mode is applied, before the first word — which is exactly when the
    /// original must already be quiet. The pocket interpreter (consecutive) covers nobody here: its rendering airs
    /// after the speaker stops (ADR-0044 LT11).
    nonisolated static func translatedSpeakers(speakers: some Sequence<String>,
                                               claims: some Sequence<SpiralAgentStateReader.AgentClaim>,
                                               language: String) -> [String: String] {
        let covered = Set(claims
            .filter { $0.lifecycle == .live && $0.translation.isActive && $0.translation.style != .consecutive }
            .flatMap(\.translation.lanes)
            .filter { $0.language == language }
            .map(\.speaker))
        var translated: [String: String] = [:]
        for speaker in speakers where covered.contains(speaker) {
            translated[speaker] = language
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
        if trackName.hasPrefix(reservedTranslationTrackPrefix) {
            return true
        }
        // The self-exclusion contract binds every subscriber in every
        // channel: a speaker never hears their own SIMULTANEOUS lane. It is
        // a property of that topology only — a consecutive `lt:<lang>`
        // track is shared and, by ADR-0044 LT11, the speaker's own clip on
        // it is meant to be heard.
        if trackName.hasPrefix(translationTrackPrefix), trackName.hasSuffix(":\(ownUserID)") {
            return true
        }
        guard let language = translationLanguage(trackName: trackName) else { return false }
        // A shared consecutive track is the pocket interpreter, communal by ADR-0044 LT11.
        guard translationSpeaker(trackName: trackName) != nil else { return false }
        return channel.language != language
    }
}
