//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0062 parity): pins the booth-model rules
// ported from `element-call/src/spiral/sheet/booths.ts` — the editor
// edits the FULL booth list, and these invariants are what keep it
// from regressing into the flat projection that erased per-speaker
// configuration on every Apply.

@testable import ElementX
import Foundation
import Testing

struct VoiceTranslationBoothsTests {
    private func booth(_ scope: VoiceSpeakerScope,
                       members: [String] = [],
                       languages: [String]) -> VoiceTranslationBooth {
        VoiceTranslationBooth(speakerScope: scope.rawValue,
                              speakerMembers: members,
                              targetLanguages: languages)
    }

    // MARK: - Simple-tier reduction

    @Test
    func onlyTheSingleAnyoneSingleLanguageCaseReducesToSimple() {
        #expect(VoiceTranslationBooths.reducesToSimple([]))
        #expect(VoiceTranslationBooths.reducesToSimple([booth(.anyone, languages: ["uk"])]))
        // Two languages, a narrower scope or a second booth all force
        // the advanced tier — collapsing them into the simple sentence
        // is exactly how configuration got silently erased.
        #expect(!VoiceTranslationBooths.reducesToSimple([booth(.anyone, languages: ["uk", "en"])]))
        #expect(!VoiceTranslationBooths.reducesToSimple([booth(.ownerOnly, languages: ["uk"])]))
        #expect(!VoiceTranslationBooths.reducesToSimple([booth(.anyone, languages: ["uk"]),
                                                         booth(.ownerOnly, languages: ["en"])]))
    }

    // MARK: - Validation

    @Test
    func everyBoothNeedsALanguageAndNamedBoothsNeedMembers() {
        #expect(!VoiceTranslationBooths.isValid([]))
        #expect(!VoiceTranslationBooths.isValid([booth(.anyone, languages: [])]))
        #expect(!VoiceTranslationBooths.isValid([booth(.specificSenders, members: [], languages: ["uk"])]))
        #expect(VoiceTranslationBooths.isValid([booth(.specificSenders, members: ["@bob:h"], languages: ["uk"])]))
        #expect(VoiceTranslationBooths.isValid([booth(.anyone, languages: ["uk"]),
                                                booth(.ownerOnly, languages: ["en"])]))
    }

    // MARK: - Locale seed

    @Test
    func theLocaleSeedMatchesTheCatalogByBaseLanguage() {
        let catalog = [VoiceControlsCatalogLanguage(code: "uk", label: "Ukrainian"),
                       VoiceControlsCatalogLanguage(code: "en", label: "English")]
        #expect(VoiceTranslationBooths.localeSeed(catalog: catalog, locale: "uk-UA") == "uk")
        #expect(VoiceTranslationBooths.localeSeed(catalog: catalog, locale: "en_GB") == "en")
        #expect(VoiceTranslationBooths.localeSeed(catalog: catalog, locale: "fr-FR") == nil)
    }

    // MARK: - Displacement (W5 / ADR-0075 D4)

    @Test
    func displacementIsAStrictCoverageShrink() {
        let broad = [booth(.anyone, languages: ["uk"])]
        // A broad booth narrowed to everyone-except is displacement.
        #expect(VoiceTranslationBooths.coverageShrank(previous: broad,
                                                      next: [booth(.everyoneExcept, members: ["@bob:h"], languages: ["uk"])]))
        // A growing exclusion list is displacement.
        #expect(VoiceTranslationBooths.coverageShrank(previous: [booth(.anyone, languages: ["uk"]),
                                                                 booth(.everyoneExcept, members: ["@bob:h"], languages: ["uk"])],
                                                      next: [booth(.anyone, languages: ["uk"]),
                                                             booth(.everyoneExcept, members: ["@bob:h", "@carol:h"], languages: ["uk"])]))
        // Losing an own-voice booth is displacement.
        #expect(VoiceTranslationBooths.coverageShrank(previous: [booth(.ownerOnly, languages: ["uk"])],
                                                      next: []))
        // A named member no longer covered is displacement.
        #expect(VoiceTranslationBooths.coverageShrank(previous: [booth(.specificSenders, members: ["@bob:h"], languages: ["uk"])],
                                                      next: [booth(.specificSenders, members: ["@carol:h"], languages: ["uk"])]))

        // NOT displacement: growth, a language change, or starting from
        // nothing.
        #expect(!VoiceTranslationBooths.coverageShrank(previous: [], next: broad))
        #expect(!VoiceTranslationBooths.coverageShrank(previous: broad,
                                                       next: [booth(.anyone, languages: ["en"])]))
        #expect(!VoiceTranslationBooths.coverageShrank(previous: [booth(.specificSenders, members: ["@bob:h"], languages: ["uk"])],
                                                       next: [booth(.anyone, languages: ["uk"])]))
    }
}
