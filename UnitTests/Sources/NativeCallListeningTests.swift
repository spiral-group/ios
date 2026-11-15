//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0063 Slice 4, revised 2026-09-02): personal
// listening is ONE switch — translation or original voices — and the
// v1 unsubscribe policy (hide a raw mic ONLY while its simultaneous lane
// is live; fail audible, never fail silent). Consecutive is communal:
// every language, every listener, the speaker's own clip included
// (ADR-0044 LT11, ADR-0075 D8).

import Foundation
@testable import Spiral
import Testing

struct NativeCallListeningTests {
    /// ADR-0094 D12: `ltd:` is reserved for a later release. Read as a raw microphone it would always play; it never
    /// does, in any channel.
    @Test
    func aReservedDeviceTrackIsNeverSubscribed() {
        for channel in [NativeCallListeningChannel.original, .translation(language: "uk")] {
            #expect(NativeCallListening.isTrackExcluded(trackName: "ltd:uk:@bob:h", channel: channel, ownUserID: "@me:h"))
        }
        #expect(NativeCallListening.isTranslationTrack(trackName: "ltd:uk:@bob:h"))
    }

    @Test
    func translationTrackNamesParseIntoLanguageAndSpeaker() {
        #expect(NativeCallListening.translationLanguage(trackName: "lt:en:@a:h") == "en")
        #expect(NativeCallListening.translationSpeaker(trackName: "lt:en:@a:h") == "@a:h")
        #expect(NativeCallListening.translationLanguage(trackName: "lt:en") == "en")
        #expect(NativeCallListening.translationSpeaker(trackName: "lt:en") == nil)
        #expect(NativeCallListening.translationLanguage(trackName: "microphone") == nil)
        #expect(NativeCallListening.translationLanguage(trackName: "lt::@a:h") == nil)
    }

    // MARK: - Channel resolution: a language, or the original (Brief 0085)

    @Test
    func aLanguageNobodyProducesIsHeardAsTheOriginal() {
        #expect(NativeCallListening.channel(choice: .language("uk"), producedLanguages: []) == .original)
        #expect(NativeCallListening.channel(choice: .language("uk"), producedLanguages: ["en"]) == .original)
        #expect(NativeCallListening.channel(choice: .original, producedLanguages: ["en", "uk"]) == .original)
    }

    @Test
    func aProducedLanguageIsHeard() {
        #expect(NativeCallListening.channel(choice: .language("uk"), producedLanguages: ["en", "uk"]) == .translation(language: "uk"))
    }

    /// Model point 1: each listener hears their own language; another language's lane is someone else's choice.
    @Test
    func onlyTheChosenLanguagesLanesAreHeard() {
        #expect(!NativeCallListening.isTrackExcluded(trackName: "lt:uk:@bob:h", channel: .translation(language: "uk"), ownUserID: "@me:h"))
        #expect(NativeCallListening.isTrackExcluded(trackName: "lt:en:@bob:h", channel: .translation(language: "uk"), ownUserID: "@me:h"))
    }

    // MARK: - Consecutive is communal (ADR-0075 D8)

    /// Consecutive survives as the pocket interpreter in the private call (Brief 0085): every shared track is heard,
    /// in turn, whatever the listener picked — the original included.
    @Test
    func everyConsecutiveLanguageIsHeard() {
        for name in ["lt:uk", "lt:en", "lt:ru"] {
            for channel in [NativeCallListeningChannel.original, .translation(language: "de")] {
                #expect(!NativeCallListening.isTrackExcluded(trackName: name, channel: channel, ownUserID: "@me:h"),
                        "\(name) must be audible")
            }
        }
    }

    /// ADR-0044 LT11: the speaker's own clip on the shared track is the
    /// feedback that stops them talking over it — heard by design. (A
    /// closeout "smarter default" briefly silenced it; reverted.)
    @Test
    func aConsecutiveSpeakerHearsTheirOwnRendering() {
        // The shared track names no speaker, so the self-exclusion suffix
        // rule cannot and must not fire on it.
        #expect(!NativeCallListening.isTrackExcluded(trackName: "lt:ru",
                                                     channel: .translation(language: "en"),
                                                     ownUserID: "@me:h"))
    }

    /// Consecutive airs AFTER the speaker stops: the live voice is never
    /// ducked for it.
    @Test
    func aConsecutiveSpeakerIsNeverDucked() {
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone",
                                                     channel: .translation(language: "en"),
                                                     ownUserID: "@me:h"))
    }

    // MARK: - Simultaneous: personal lanes, self-excluded

    @Test
    func aSpeakerNeverHearsTheirOwnSimultaneousLaneInAnyChannel() {
        for channel in [NativeCallListeningChannel.translation(language: "en"), .original] {
            #expect(NativeCallListening.isTrackExcluded(trackName: "lt:en:@me:h",
                                                        channel: channel,
                                                        ownUserID: "@me:h"))
        }
    }

    /// Brief 0066 — a raw microphone is never UNSUBSCRIBED by listening:
    /// while its simultaneous lane is live it is DUCKED on the device (the
    /// plan's `originalDucking` names whom — pinned in
    /// `NativeCallOriginalDuckingTests`).
    @Test
    func aRawMicStaysSubscribedWhateverItsLaneDoes() {
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone", channel: .translation(language: "en"), ownUserID: "@me:h"))
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone", channel: .original, ownUserID: "@me:h"))
    }

    /// Brief 0066 rev. 2 — the original under a translation is a quiet bed,
    /// never silence: 15 % of full scale keeps the speaker's tone and pacing.
    @Test
    func theOriginalGainIsAQuietBedNotSilence() {
        #expect(NativeCallListening.originalGain == 0.15)
    }

    /// Whose lanes a document airs → who is heard in translation, by the rule the derivation applies (pinned in full
    /// in `NativeCallStateDerivationTests`): Live style, live lifecycle, active lanes into the listener's language, in
    /// its exact code; the pocket interpreter and a standby cover nobody.
    @Test
    func translatedSpeakersFollowLiveLanesOnly() {
        let live = SpiralAgentStateReader.AgentClaim.make(languages: ["pt-BR"], style: .simultaneous, speakers: ["@bob:h"])
        let interpreter = SpiralAgentStateReader.AgentClaim.make(languages: ["en", "uk"], style: .consecutive, speakers: ["@bob:h"])
        let leaving = SpiralAgentStateReader.AgentClaim.make(languages: ["de"], style: .simultaneous, speakers: ["@bob:h"], lifecycle: .leaving)
        let standby = SpiralAgentStateReader.AgentClaim.make(translation: .init(isActive: false, style: .simultaneous, source: .roomTool, forLanguage: "fr",
                                                                                 pocket: nil, owner: nil, lanes: [], stoppedReason: nil))

        #expect(NativeCallListening.translatedSpeakers(speakers: ["@bob:h", "@carol:h"], claims: [live], language: "pt-BR") == ["@bob:h": "pt-BR"])
        #expect(NativeCallListening.translatedSpeakers(speakers: ["@bob:h"], claims: [live], language: "pt-PT").isEmpty, "exact codes, not the base")
        #expect(NativeCallListening.translatedSpeakers(speakers: ["@bob:h"], claims: [interpreter, leaving], language: "en").isEmpty)
        #expect(NativeCallListening.translatedSpeakers(speakers: ["@bob:h"], claims: [standby], language: "fr").isEmpty)
    }

    /// Track names carry the catalog's exact code (A.6): `lt:zh-Hans:…` is `zh-Hans`, never `zh`.
    @Test
    func aTrackNameKeepsTheExactCode() {
        #expect(NativeCallListening.translationLanguage(trackName: "lt:zh-Hans:@bob:h") == "zh-Hans")
        #expect(NativeCallListening.translationLanguage(trackName: "lt:pt-BR") == "pt-BR")
        #expect(NativeCallListening.translationSpeaker(trackName: "lt:zh-Hans:@bob:h") == "@bob:h")
    }

    @Test
    func anotherSpeakersLaneIsHeard() {
        #expect(!NativeCallListening.isTrackExcluded(trackName: "lt:en:@bob:h",
                                                     channel: .translation(language: "en"),
                                                     ownUserID: "@me:h"))
    }

    // MARK: - Original voices only

    @Test
    func originalUnsubscribesEveryLiveLaneAndRestoresEveryRawVoice() {
        for name in ["lt:en:@bob:h", "lt:uk:@carol:h"] {
            #expect(NativeCallListening.isTrackExcluded(trackName: name,
                                                        channel: .original,
                                                        ownUserID: "@me:h"))
        }
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone",
                                                     channel: .original,
                                                     ownUserID: "@me:h"))
    }
}
