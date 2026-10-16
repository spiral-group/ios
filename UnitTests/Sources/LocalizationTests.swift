//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import ElementX
import Foundation
import Testing

final class LocalizationTests {
    deinit {
        Bundle.overrideLocalizations = nil
    }
    
    /// Test ElementL10n considers app language changes
    @Test
    func appLanguage() {
        // set app language to English
        Bundle.overrideLocalizations = ["en"]
        
        #expect(L10n.testLanguageIdentifier == "en")
        
        // set app language to Italian
        Bundle.overrideLocalizations = ["it"]
        
        #expect(L10n.testLanguageIdentifier == "it")
    }
    
    /// Test fallback language for a language not supported at all
    @Test
    func fallbackOnNotSupportedLanguage() {
        //  set app language to something Element don't support at all (chose non existing identifier)
        Bundle.overrideLocalizations = ["xx"]
        
        #expect(L10n.testLanguageIdentifier == "en")
    }
    
    /// Test fallback language for a language supported but poorly translated
    @Test
    func fallbackOnNotTranslatedKey() {
        //  set app language to something Element supports but use a key that is not translated (we have a key that should never be translated)
        Bundle.overrideLocalizations = ["it"]
        
        #expect(L10n.testLanguageIdentifier == "it")
        #expect(L10n.testUntranslatedDefaultLanguageIdentifier == "en")
    }
    
    /// Test plurals that ElementL10n considers app language changes
    @Test
    func plurals() {
        //  set app language to English
        Bundle.overrideLocalizations = ["en"]
        
        #expect(L10n.commonMemberCount(1) == "1 Member")
        #expect(L10n.commonMemberCount(2) == "2 Members")
        
        //  set app language to Italian
        Bundle.overrideLocalizations = ["it"]
        
        #expect(L10n.commonMemberCount(1) == "1 Membro")
        #expect(L10n.commonMemberCount(2) == "2 Membri")
    }
    
    /// Test plurals fallback language for a language not supported at all
    @Test
    func pluralsFallbackOnNotSupportedLanguage() {
        //  set app language to something Element don't support at all ("invalid identifier")
        Bundle.overrideLocalizations = ["xx"]
        
        #expect(L10n.commonMemberCount(1) == "1 Member")
        #expect(L10n.commonMemberCount(2) == "2 Members")
    }
    
    /// Test untranslated strings
    @Test
    func untranslated() {
        #expect(UntranslatedL10n.untranslated == "Untranslated")
        #expect(UntranslatedL10n.untranslatedPlural(1) == "One untranslated item")
        #expect(UntranslatedL10n.untranslatedPlural(5) == "5 untranslated items")
    }

    // AGENT-PLATFORM: the fork now ships translations of the Untranslated table
    // (`UntranslatedL10n.tr` resolves through the user's preferred languages,
    // not just en). Prove the pipeline: a translated key follows the app
    // language, and a key a locale doesn't carry falls back to en.
    @Test
    func untranslatedFollowsAppLanguage() {
        Bundle.overrideLocalizations = ["uk"]
        #expect(UntranslatedL10n.commonOn == "Увімк.")
        #expect(UntranslatedL10n.actionApprovalApprove == "Схвалити")

        Bundle.overrideLocalizations = ["ru"]
        #expect(UntranslatedL10n.commonOn == "Вкл.")
        #expect(UntranslatedL10n.actionApprovalApprove == "Одобрить")

        // A locale we don't support at all falls back to en.
        Bundle.overrideLocalizations = ["xx"]
        #expect(UntranslatedL10n.commonOn == "On")

        // The test fixture is deliberately en-only, so it must stay "On"/"…"
        // even under a supported non-en locale.
        Bundle.overrideLocalizations = ["uk"]
        #expect(UntranslatedL10n.untranslated == "Untranslated")
    }

    // AGENT-PLATFORM (Brief 0063 audit C11b): uk/ru parity for the call surface.
    /// The call surface is fully translated in the two locales we actually
    /// ship to (audit C11b).
    ///
    /// Before this, uk and ru carried 297 of en's 486 keys — every string
    /// added by Brief 0063 was missing, so the whole native call screen
    /// rendered in English for a Ukrainian or Russian user while the rest
    /// of the app was translated. Nothing watched for that: the gap grew
    /// silently over four months because no test compared the files.
    ///
    /// Deliberately only uk and ru. The other 36 locales keep the English
    /// fallback rather than carry unreviewed machine output, which is the
    /// honest state — a correct English word beats a confidently wrong
    /// German one.
    @Test
    func theCallSurfaceIsTranslatedWhereWeClaimItIs() {
        // A spread across the screen: status line, controls, agent centre,
        // an accessibility label, and one with a placeholder.
        Bundle.overrideLocalizations = ["uk"]
        #expect(UntranslatedL10n.screenNativeCallStatusWaiting == "Очікуємо на інших…")
        #expect(UntranslatedL10n.screenNativeCallControlEnd == "Завершити")
        #expect(UntranslatedL10n.screenNativeCallAgentCenterTitle == "Центр агентів")
        #expect(UntranslatedL10n.a11yNativeCallEnd == "Завершити дзвінок")
        #expect(UntranslatedL10n.screenNativeCallAgentCenterTranslationOn("усіх на німецьку") == "Перекладає усіх на німецьку")

        Bundle.overrideLocalizations = ["ru"]
        #expect(UntranslatedL10n.screenNativeCallStatusWaiting == "Ждём других…")
        #expect(UntranslatedL10n.screenNativeCallControlEnd == "Завершить")
        #expect(UntranslatedL10n.screenNativeCallAgentCenterTitle == "Центр агентов")
        #expect(UntranslatedL10n.a11yNativeCallEnd == "Завершить звонок")

        // A locale we deliberately did NOT translate still falls back to en,
        // which is the point of leaving it alone rather than machine-filling
        // it.
        Bundle.overrideLocalizations = ["de"]
        #expect(UntranslatedL10n.screenNativeCallControlEnd == "End")
    }

    // AGENT-PLATFORM: the call-summary / call-recording tools (Brief 0046) and
    // the multi-language live-translate picker shipped English-only. Prove the
    // newly added translations now follow the app language across scripts, and
    // that an unsupported locale still falls back to en.
    @Test
    func callToolStringsFollowAppLanguage() {
        Bundle.overrideLocalizations = ["uk"]
        #expect(UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle == "Підсумовувати дзвінки")
        #expect(UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle == "Записувати дзвінки")
        #expect(UntranslatedL10n.screenArmToolLanguageAdd == "Додати мову")

        Bundle.overrideLocalizations = ["ru"]
        #expect(UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle == "Подводить итоги звонков")
        #expect(UntranslatedL10n.screenArmToolCallRecordingTitle == "Записывать звонки")

        Bundle.overrideLocalizations = ["zh-Hans"]
        #expect(UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle == "录制通话")

        // An unsupported locale falls back to the en source string.
        Bundle.overrideLocalizations = ["xx"]
        #expect(UntranslatedL10n.screenArmToolCallSummaryTitle == "Summarise calls")
    }

    // AGENT-PLATFORM (§ 5.59): completeness, not a sample.
    /// uk and ru carry every string the fork adds, with the same placeholders.
    ///
    /// The spot checks above prove the pipeline, not coverage, and coverage
    /// is what slipped twice: the call surface went four months English-only
    /// in both languages (C11b), and the interactive posts' 37 strings went
    /// two weeks — both because nothing compared the files. The en-only
    /// sentinels exist to prove the fallback and are the only exceptions.
    @Test
    func ukrainianAndRussianCarryEveryForkString() throws {
        let sentinels: Set = ["untranslated", "untranslated_plural"]
        let english = try untranslatedTable("en")
        #expect(english.count > 400, "the en table did not load")

        for language in ["uk", "ru"] {
            let translated = try untranslatedTable(language)
            let missing = Set(english.keys).subtracting(translated.keys).subtracting(sentinels)
            #expect(missing.isEmpty, "\(language) is missing \(missing.sorted())")

            for (key, source) in english where !sentinels.contains(key) {
                guard let value = translated[key] else { continue }
                #expect(Self.placeholders(value) == Self.placeholders(source),
                        "\(language).\(key) has placeholders \(Self.placeholders(value)), en has \(Self.placeholders(source))")
            }
        }
    }

    /// Every key and value of a locale's Untranslated table — .strings and
    /// .stringsdict; a plural's value is its format key, for the check above.
    private func untranslatedTable(_ language: String) throws -> [String: String] {
        let bundle = try #require(Bundle.lprojBundle(for: language), "no \(language).lproj in the app")
        var table: [String: String] = [:]
        if let url = bundle.url(forResource: "Untranslated", withExtension: "strings"),
           let strings = NSDictionary(contentsOf: url) as? [String: String] {
            table.merge(strings) { first, _ in first }
        }
        if let url = bundle.url(forResource: "Untranslated", withExtension: "stringsdict"),
           let plurals = NSDictionary(contentsOf: url) as? [String: Any] {
            for (key, entry) in plurals {
                table[key] = ((entry as? [String: Any])?["NSStringLocalizedFormatKey"] as? String) ?? ""
            }
        }
        return table
    }

    // AGENT-PLATFORM (ADR-0088): room tools are turned on in the app, never by
    // chat. The assistant's welcome used to promise it would "set up tools for
    // groups" if written to; it now points at the menu item, so the copy must
    // keep naming the item the composer's + menu actually shows.
    @Test(arguments: ["en", "uk", "ru"])
    func theWelcomeNamesTheMenuWhereToolsAre(language: String) {
        Bundle.overrideLocalizations = [language]
        #expect(UntranslatedL10n.noticeWelcomeAssistantBody("Aria").contains(UntranslatedL10n.screenRoomAttachmentAgentTools))
    }

    private static func placeholders(_ format: String) -> [String] {
        format.matches(of: /%(?:\d+\$)?[@dlfs]/).map { String($0.output) }.sorted()
    }
}
