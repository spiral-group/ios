//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import MatrixRustSDK
@testable import Spiral
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
    
    /// AGENT-PLATFORM (question 357): Spiral's value in a language's Untranslated table beats the synced Localizable.
    @Test
    func spiralValueWinsOverLocalizable() {
        Bundle.overrideLocalizations = ["ru"]
        
        #expect(L10n.screenSearchEmptyStateTitle == "Начните поиск…")
        #expect(L10n.commonNoResultsFor("кот") == "Нет результатов по запросу «кот». Попробуйте другой запрос.")
        #expect(L10n.actionForwardMessages(2) == "Переслать 2 сообщения")
        #expect(L10n.actionForwardMessages(5) == "Переслать 5 сообщений")
        
        // Ukrainian's Localizable has this one empty.
        Bundle.overrideLocalizations = ["uk"]
        #expect(L10n.screenSearchTabMessages == "Повідомлення")
        // The search tab says what the Chats tab says.
        #expect(L10n.screenSearchTabChats == L10n.screenHomeTabChats)
    }
    
    /// A key Spiral doesn't carry still reads Localizable.
    @Test
    func localizableStaysTheDefault() {
        Bundle.overrideLocalizations = ["ru"]
        
        #expect(L10n.actionContinue == "Продолжить")
    }
    
    /// A sync that brings English into Russian fails here: give the key a value in ru's Untranslated.strings.
    @Test
    func russianHasNoEnglishLeft() throws {
        let english = try #require(Bundle.lprojBundle(for: "en"))
        let russian = try #require(Bundle.lprojBundle(for: "ru"))
        let url = try #require(english.url(forResource: "Localizable", withExtension: "strings"))
        let keys = try #require(NSDictionary(contentsOf: url)?.allKeys as? [String])
        
        let inEnglish = keys.filter { key in
            let spiral = NSLocalizedString(key, tableName: "Untranslated", bundle: russian, comment: "")
            let value = spiral != key ? spiral : NSLocalizedString(key, tableName: "Localizable", bundle: russian, comment: "")
            return value == NSLocalizedString(key, tableName: "Localizable", bundle: english, comment: "")
        }
        
        #expect(Set(inEnglish) == sameInEveryLanguage)
    }
    
    /// Brands, formats with no words, an address and the test fixture. "Element Fade" is stripped from a Release build.
    private let sameInEveryLanguage: Set = ["common_face_id_ios",
                                            "common_gif",
                                            "common_name_and_id",
                                            "common_optic_id_ios",
                                            "common_sentence_delimiter",
                                            "common_touch_id_ios",
                                            "crypto_identity_change_pin_violation_new_user_id",
                                            "login_initial_device_name_ios",
                                            "notification_ticker_text_dm",
                                            "notification_ticker_text_group",
                                            "screen_change_server_error_element_pro_required_action_ios",
                                            "screen_change_server_textfield_placeholder",
                                            "screen_create_poll_option_accessibility_label",
                                            "screen_notification_settings_sound_element_fade",
                                            "screen_space_list_details",
                                            "test_untranslated_default_language_identifier"]
    
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
    /// Question 305 (1.0.2) brought the rest of the shipped locales along;
    /// `everyLocaleCarriesEveryForkString` keeps them complete.
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

        Bundle.overrideLocalizations = ["de"]
        #expect(UntranslatedL10n.screenNativeCallControlEnd == "Beenden")
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

        Bundle.overrideLocalizations = ["ru"]
        #expect(UntranslatedL10n.screenAgentCapabilitiesCallSummaryTitle == "Подводить итоги звонков")
        #expect(UntranslatedL10n.screenArmToolCallRecordingTitle == "Записывать звонки")

        Bundle.overrideLocalizations = ["zh-Hans"]
        #expect(UntranslatedL10n.screenAgentCapabilitiesCallRecordingTitle == "录制通话")

        // An unsupported locale falls back to the en source string.
        Bundle.overrideLocalizations = ["xx"]
        #expect(UntranslatedL10n.screenArmToolCallSummaryTitle == "Summarise calls")
    }

    // AGENT-PLATFORM (§ 5.59, question 305): completeness, not a sample.
    /// Every shipped locale carries every string the fork adds, with the same placeholders.
    ///
    /// The spot checks above prove the pipeline, not coverage, and coverage
    /// is what slipped: the call surface went four months English-only in uk
    /// and ru (C11b), the interactive posts' 37 strings went two weeks, and
    /// until question 305 a German user saw a third of the app in English —
    /// each time because nothing compared the files. The en-only sentinels
    /// exist to prove the fallback and are the only exceptions; en-US carries
    /// only spelling overrides and falls back to en.
    @Test
    func everyLocaleCarriesEveryForkString() throws {
        let sentinels: Set = ["untranslated", "untranslated_plural"]
        let english = try untranslatedTable("en")
        #expect(english.count > 1400, "the en table did not load")
        let languages = Bundle.app.localizations.filter { !["Base", "en", "en-US"].contains($0) }
        #expect(languages.count == 39)

        for language in languages {
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

    /// A plural's every category carries the placeholders of en's `other`: a `%1$@` in place of `%1$d` in one
    /// category would crash only for that count. Arabic and Welsh may name zero, one and two without the number.
    @Test
    func everyPluralCategoryKeepsItsPlaceholders() throws {
        let english = try untranslatedPlurals("en")
        #expect(english.count > 20, "the en plurals did not load")

        for language in Bundle.app.localizations where !["Base", "en", "en-US"].contains(language) {
            for (key, variables) in try untranslatedPlurals(language) {
                guard let sourceVariables = english[key] else { continue }
                for (variable, categories) in variables {
                    let expected = try #require(sourceVariables[variable]?["other"].map(Self.placeholders), "\(language).\(key).\(variable)")
                    #expect(categories["other"] != nil, "\(language).\(key).\(variable) has no other")
                    for (category, value) in categories where Self.placeholders(value) != expected {
                        let namesTheCount = ["ar", "cy"].contains(language) && ["zero", "one", "two"].contains(category)
                        #expect(namesTheCount && Self.placeholders(value).isEmpty,
                                "\(language).\(key).\(variable).\(category) has \(Self.placeholders(value)), en has \(expected)")
                    }
                }
            }
        }
    }

    // AGENT-PLATFORM (1.0.2): a German feed read «Pinned» beside «Weiterlesen».
    @Test
    func theFeedReadsInOneLanguage() {
        Bundle.overrideLocalizations = ["de"]
        #expect(UntranslatedL10n.screenFeedPinnedLabel == "Fixiert")
        #expect(UntranslatedL10n.screenFeedReadMore == "Weiterlesen")
    }

    // AGENT-PLATFORM (Brief 0083 L1b, decision 302): the keys that replace
    // Element-branded upstream strings are in every locale the app ships, so
    // none of them falls back to en, and none names Element.
    @Test
    func spiralNamesForElementStringsAreInEveryLocale() throws {
        let overrides = ["screen_notification_settings_sound_spiral_default",
                         "screen_notification_settings_sound_spiral_fade",
                         "screen_room_timeline_legacy_call_spiral"]
        let languages = Bundle.app.localizations.filter { $0 != "Base" }
        #expect(languages.count == 41, "decision 302 keeps Element X's 41 languages")

        for language in languages {
            let table = try untranslatedTable(language)
            for key in overrides {
                let value = try #require(table[key], "\(language) has no \(key)")
                #expect(value.contains("Spiral") && !value.contains("Element"), "\(language).\(key) is \(value)")
            }
        }
    }

    // AGENT-PLATFORM (question 404, operator 2026-11-12): the "one recording
    // per call" card and confirmation put the owner's name first, as the
    // sentence's subject, in the present tense — so no language declines the
    // name or agrees a verb with its gender. Every locale keeps the one name
    // placeholder, and the card's own line names no one.
    @Test
    func aRecordingOwnersNameIsTheSubject() throws {
        Bundle.overrideLocalizations = ["en"]
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordingCovered("Bohdan") == "Bohdan is already recording this call")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterOther("Bohdan")
            == "Bohdan is no longer recording. Your recording will come to the chat as a separate file.")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredButton == "Recording")

        Bundle.overrideLocalizations = ["uk"]
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordingCovered("Богдан") == "Богдан уже записує цей дзвінок")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredSomeone == "Хтось уже записує цей дзвінок")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredCardDetail
            == "Файл прийде в цей чат. Коли запис зупиниться, тут з’явиться «\(UntranslatedL10n.screenNativeCallAssistantsRecordingContinue)».")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredGotIt == "Зрозуміло")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterOther("Богдан")
            == "Богдан більше не записує. Ваш запис з’явиться в чаті окремим файлом.")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterSomeone
            == "Попередній запис зупинено. Ваш запис з’явиться в чаті окремим файлом.")

        Bundle.overrideLocalizations = ["ru"]
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordingCovered("Богдан") == "Богдан уже записывает этот звонок")
        #expect(UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterOther("Богдан")
            == "Богдан больше не записывает. Ваша запись появится в чате отдельным файлом.")
        Bundle.overrideLocalizations = nil

        for language in Bundle.app.localizations where language != "Base" {
            let table = try untranslatedTable(language)
            for key in ["screen_native_call_assistants_recording_covered", "screen_native_call_assistants_record_confirm_message_after_other"] {
                let value = try #require(table[key], "\(language) has no \(key)")
                #expect(Self.placeholders(value) == ["%1$@"], "\(language).\(key) is \(value)")
            }
            // The card's line names the button it promises.
            let detail = try #require(table["screen_native_call_assistants_recording_covered_card_detail"], "\(language) has no card line")
            let resume = try #require(table["screen_native_call_assistants_recording_continue"])
            #expect(detail.contains(resume), "\(language)'s card line doesn't name «\(resume)»: \(detail)")
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

    /// A locale's Untranslated.stringsdict as key → variable → category → format.
    private func untranslatedPlurals(_ language: String) throws -> [String: [String: [String: String]]] {
        let bundle = try #require(Bundle.lprojBundle(for: language), "no \(language).lproj in the app")
        guard let url = bundle.url(forResource: "Untranslated", withExtension: "stringsdict"),
              let plurals = NSDictionary(contentsOf: url) as? [String: [String: Any]] else { return [:] }
        return plurals.mapValues { entry in
            entry.compactMapValues { $0 as? [String: String] }.mapValues { rules in
                rules.filter { ["zero", "one", "two", "few", "many", "other"].contains($0.key) }
            }
        }
    }

    // AGENT-PLATFORM (dev walk 2026-11-13): the assistant's banner on Dev-A read «Thread» and
    // «Draft - Голосування з іменами». Both words are the NSE's own, from these keys; the NSE
    // follows the phone's language, and Dev-A's is en-US (only the app gets `-AppleLanguages (uk)`).
    // The title is the post's own. On a phone in Ukrainian the banner reads as below.
    @Test
    func theAssistantsDraftBannerReadsInTheLanguage() {
        let draft = InteractiveDraftContent(body: "", title: "Голосування з іменами", aspect: "1:1",
                                            manifestJson: "{}", source: "", sha256: String(repeating: "0", count: 64),
                                            version: 1, generatedByAgentId: nil, targetRoomId: "!r:spiral.md")
        let builder = RoomMessageEventStringBuilder(attributedStringBuilder: AttributedStringBuilder(mentionBuilder: PlainMentionBuilder()),
                                                    style: .plain)
        func banner() -> String {
            String(builder.buildAttributedString(for: .interactiveDraft(content: draft), senderID: "@assistant-aria:spiral.md", senderDisplayName: "Aria", isOutgoing: false).characters)
        }

        Bundle.overrideLocalizations = ["uk"]
        #expect(L10n.commonThread == "Гілка")
        #expect(banner() == "Чернетка - Голосування з іменами")

        Bundle.overrideLocalizations = ["ru"]
        #expect(L10n.commonThread == "Обсуждение")
        #expect(banner() == "Черновик - Голосування з іменами")
    }

    private static func placeholders(_ format: String) -> [String] {
        format.matches(of: /%(?:\d+\$)?[@dlfs]/).map { String($0.output) }.sorted()
    }
}
