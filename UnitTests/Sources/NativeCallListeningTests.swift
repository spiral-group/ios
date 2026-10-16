//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0063 Slice 4, revised 2026-09-02): personal
// listening is ONE switch — translation or original voices — and the
// v1 unsubscribe policy (hide a raw mic ONLY while its simultaneous lane
// is live; fail audible, never fail silent). Consecutive is communal:
// every language, every listener, the speaker's own clip included
// (ADR-0044 LT11, ADR-0075 D8).

@testable import ElementX
import Foundation
import Testing

struct NativeCallListeningTests {
    // MARK: - Produced languages

    @Test
    func producedLanguagesAreTheSortedUnionOfTranslationTracks() {
        let names = ["microphone", "lt:uk:@a:h", "lt:en:@a:h", "lt:en:@b:h", "screen", "lt:"]
        #expect(NativeCallListening.producedLanguages(trackNames: names) == ["en", "uk"])
        #expect(NativeCallListening.producedLanguages(trackNames: ["microphone"]).isEmpty)
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

    // MARK: - Channel resolution: one switch

    @Test
    func withoutTranslationTheChannelIsEverythingWhateverTheSwitchSays() {
        // Nothing produced, nothing to refuse — never a silence the user
        // did not ask for.
        #expect(NativeCallListening.channel(choice: .translation, producedLanguages: []) == .everything)
        #expect(NativeCallListening.channel(choice: .original, producedLanguages: []) == .everything)
    }

    @Test
    func theSwitchResolvesToEverythingOrOriginal() {
        #expect(NativeCallListening.channel(choice: .translation, producedLanguages: ["en", "uk"]) == .everything)
        #expect(NativeCallListening.channel(choice: .original, producedLanguages: ["en", "uk"]) == .original)
    }

    // MARK: - Consecutive is communal (ADR-0075 D8)

    /// The iOS port used to enforce a per-language pick on consecutive by
    /// unsubscribing every OTHER language's shared track — a call configured
    /// ru+en played one of them. There is no such pick any more: every
    /// consecutive track is heard, in turn, by everyone.
    @Test
    func everyConsecutiveLanguageIsHeard() {
        for name in ["lt:uk", "lt:en", "lt:ru"] {
            #expect(!NativeCallListening.isTrackExcluded(trackName: name,
                                                         channel: .everything,
                                                         ownUserID: "@me:h"),
                    "\(name) must be audible")
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
                                                     channel: .everything,
                                                     ownUserID: "@me:h"))
    }

    /// Consecutive airs AFTER the speaker stops: the live voice is never
    /// ducked for it.
    @Test
    func aConsecutiveSpeakerIsNeverDucked() {
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone",
                                                     channel: .everything,
                                                     ownUserID: "@me:h"))
    }

    // MARK: - Simultaneous: personal lanes, self-excluded

    @Test
    func aSpeakerNeverHearsTheirOwnSimultaneousLaneInAnyChannel() {
        for channel in [NativeCallListeningChannel.everything, .original] {
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
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone", channel: .everything, ownUserID: "@me:h"))
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone", channel: .original, ownUserID: "@me:h"))
    }

    /// Brief 0066 rev. 2 — the original under a translation is a quiet bed,
    /// never silence: 15 % of full scale keeps the speaker's tone and pacing.
    @Test
    func theOriginalGainIsAQuietBedNotSilence() {
        #expect(NativeCallListening.originalGain == 0.15)
    }

    /// Who a document covers → who is heard in translation, by the rule
    /// the derivation applies (pinned in full in
    /// `NativeCallStateDerivationTests`): Live style, live lifecycle,
    /// active booths; Interpreter covers nobody; the smallest tag wins.
    @Test
    func translatedSpeakersFollowLiveBoothsOnly() {
        let live = SpiralAgentStateReader.AgentClaim.make(languages: ["uk"], style: .simultaneous,
                                                          booths: [.init(coverage: .members(["@bob:h"]), targetLanguages: ["uk"])])
        let interpreter = SpiralAgentStateReader.AgentClaim.make(languages: ["en"], style: .consecutive)
        let leaving = SpiralAgentStateReader.AgentClaim.make(languages: ["de"], style: .simultaneous, lifecycle: .leaving)
        let unstyled = SpiralAgentStateReader.AgentClaim.make(languages: ["fr", "en"])

        #expect(NativeCallListening.translatedSpeakers(speakers: ["@bob:h", "@carol:h"], claims: [live]) == ["@bob:h": "uk"])
        #expect(NativeCallListening.translatedSpeakers(speakers: ["@bob:h"], claims: [interpreter, leaving]).isEmpty)
        #expect(NativeCallListening.translatedSpeakers(speakers: ["@bob:h"], claims: [live, unstyled]) == ["@bob:h": "en"],
                "no style reads as Live (the wire default) and the smallest tag wins")
    }

    @Test
    func anotherSpeakersLaneIsHeard() {
        #expect(!NativeCallListening.isTrackExcluded(trackName: "lt:en:@bob:h",
                                                     channel: .everything,
                                                     ownUserID: "@me:h"))
    }

    // MARK: - Original voices only

    @Test
    func originalUnsubscribesEveryTranslationAndRestoresEveryRawVoice() {
        for name in ["lt:en", "lt:uk", "lt:en:@bob:h"] {
            #expect(NativeCallListening.isTrackExcluded(trackName: name,
                                                        channel: .original,
                                                        ownUserID: "@me:h"))
        }
        #expect(!NativeCallListening.isTrackExcluded(trackName: "microphone",
                                                     channel: .original,
                                                     ownUserID: "@me:h"))
    }
}
