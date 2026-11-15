//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, question 403): the 文A button, top right of the call. It is there when the people in the
// call speak different languages or a translation runs, and only then; a dot marks a language that appeared since the
// menu was last opened; blue with the language's code while you hear a translation. A tap opens the system menu
// "Listen to the call", the call's audio tracks (L4): the original, the translations there are (free unless they are
// your assistant's, "2 of 3 · free" when they cover only some speakers), and "+ Add your translation", which opens the
// Assistants sheet at creating one. What you hear is only yours (ADR-0075 D7).

import Compound
import SpiralTokens
import SwiftUI

struct NativeCallTranslateButton: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var translation: NativeCallTranslationState {
        context.viewState.translation
    }

    var body: some View {
        if translation.isButtonVisible {
            Menu {
                menuContent
                    // The menu's content appears as it opens: its new languages are seen, and the dot goes.
                    .onAppear { context.send(viewAction: .translateMenuOpened) }
            } label: {
                label
            }
            // The tracks first, as the board draws them, wherever the button sits.
            .menuOrder(.fixed)
            .accessibilityLabel(UntranslatedL10n.screenNativeCallTranslateMenuTitle)
            .accessibilityValue(accessibilityValue)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Label

    private var label: some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            Image(systemName: "translate")
                .font(.compound.bodyLGSemibold)
            if let language = translation.listeningLanguage {
                // Codes read left to right in every layout direction.
                Text(verbatim: NativeCallAgentPillContent.code(language))
                    .font(.compound.bodySMSemibold)
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .foregroundStyle(translation.listeningLanguage == nil ? Color.compound.iconPrimary : Color.compound.iconOnSolidPrimary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, translation.listeningLanguage == nil ? 0 : CompoundDesignTokens.space3X)
        .frame(minWidth: 44, minHeight: 44)
        .background {
            if translation.listeningLanguage != nil {
                Capsule().fill(Color.compound.bgAccentRest)
            }
        }
        .nativeCallSurface(in: Capsule(), isInteractive: true)
        .overlay(alignment: .topTrailing) {
            if translation.hasNewLanguage {
                Circle()
                    .fill(Color.compound.iconAccentPrimary)
                    .frame(width: 10, height: 10)
                    .overlay { Circle().stroke(Color.compound.bgCanvasDefault, lineWidth: 1.5) }
                    .offset(x: 1, y: -1)
                    .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: translation.listeningLanguage)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let language = translation.listeningLanguage {
            parts.append(UntranslatedL10n.a11yNativeCallTranslateListening(NativeCallAgentStatusCopy.languageName(language)))
        }
        if translation.hasNewLanguage {
            parts.append(UntranslatedL10n.a11yNativeCallTranslateNew)
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Menu

    /// L4: the call's audio tracks — the original, the translations there are with whose assistant makes them and that
    /// they're free, the stopped ones to continue — then your own translation, then «Я говорю» (question 409, option A).
    @ViewBuilder
    private var menuContent: some View {
        let items = NativeCallTranslateMenuItem.items(translation)
        Section(UntranslatedL10n.screenNativeCallTranslateMenuTitle) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .original(let isSelected):
                    choice(title: UntranslatedL10n.screenNativeCallTranslateOriginal,
                           detail: UntranslatedL10n.screenNativeCallTranslateOriginalDetail,
                           isSelected: isSelected) {
                        context.send(viewAction: .setListeningChoice(.original))
                    }
                case .track(let option, let isSelected):
                    choice(title: NativeCallTranslationCopy.languageTitle(option.language),
                           detail: NativeCallTranslationCopy.optionDetail(option, context: context),
                           isSelected: isSelected) {
                        context.send(viewAction: .setListeningChoice(.language(option.language)))
                    }
                case .stopped(let language):
                    // «Английский · Перевод остановлен · Продолжить», the capsule's event kept: a button, not a pick, since
                    // continuing starts your own assistant's paid work.
                    Button {
                        context.send(viewAction: .continueTranslation(language: language))
                    } label: {
                        Text(NativeCallTranslationCopy.languageTitle(language))
                        Text(NativeCallTranslationCopy.stoppedDetail)
                    }
                case .own, .spokenLanguage:
                    EmptyView()
                }
            }
        }
        // L7: the title alone. The tracks are toggles, which reserve the checkmark column; an image here would sit in a
        // second column after it and push the title far past the original's.
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            switch item {
            case .own(let isRunning):
                Section {
                    Button(isRunning ? UntranslatedL10n.screenNativeCallTranslateOwn : UntranslatedL10n.screenNativeCallTranslateAddOwn) {
                        context.send(viewAction: .addOwnTranslation)
                    }
                }
            case .spokenLanguage(let language):
                Section {
                    spokenLanguageMenu(language)
                }
            case .original, .track, .stopped:
                EmptyView()
            }
        }
    }

    /// Question 409: «Я говорю» with your language under it; inside, the likely languages to pick at once and «Інша мова…»,
    /// the whole list the capsule's «Змінити» opens. A pick is your choice of «Моя мова», as in the list.
    private func spokenLanguageMenu(_ language: String) -> some View {
        Menu {
            Picker(UntranslatedL10n.screenNativeCallAssistantsISpeak,
                   selection: Binding(get: { language }, set: { pickSpokenLanguage($0) })) {
                ForEach(likelyLanguages(current: language), id: \.self) { code in
                    Text(NativeCallTranslationCopy.languageTitle(code)).tag(code)
                }
            }
            .pickerStyle(.inline)
            Section {
                Button(UntranslatedL10n.screenNativeCallTranslateOtherLanguage) {
                    context.send(viewAction: .showSpokenLanguage)
                }
            }
        } label: {
            Text(UntranslatedL10n.screenNativeCallAssistantsISpeak)
            Text(NativeCallTranslationCopy.languageTitle(language))
        }
        .menuOrder(.fixed)
    }

    /// Every list's rule (`SuggestedLanguages`), at most four in a menu.
    private func likelyLanguages(current: String) -> [String] {
        SuggestedLanguages.onDevice(selected: current, catalog: context.viewState.languageCodes, limit: 4)
    }

    private func pickSpokenLanguage(_ language: String) {
        guard language != context.viewState.myLanguage else { return }
        context.send(viewAction: .setMyLanguage(language == context.viewState.phoneLanguage ? nil : language))
    }

    /// A pick with a checkmark, as the system draws a toggle in a menu, and its detail under the title.
    private func choice(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in action() })) {
            Text(title)
            Text(detail)
        }
    }
}

/// Every word about the call's translation, in one place.
enum NativeCallTranslationCopy {
    /// A language as a title: "Ukrainian", capitalised where the language writes it in lower case.
    static func languageTitle(_ code: String) -> String {
        let name = NativeCallAgentStatusCopy.languageName(code)
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Whether a search finds a language, by the name its row shows (`TranslationLanguageDisplayName.matches`).
    static func language(_ code: String, matches query: String) -> Bool {
        TranslationLanguageDisplayName.matches(query, code: code, shownName: languageTitle(code))
    }

    /// The languages a search finds, in their order.
    static func languages(_ codes: [String], matching query: String) -> [String] {
        codes.filter { language($0, matches: query) }
    }

    /// A language inside a sentence, as the system names it ("украинский").
    static func languageName(_ code: String) -> String {
        NativeCallAgentStatusCopy.languageName(code)
    }

    /// "Bohdan's assistant · free", "1 of 2 · Bohdan's assistant · free", "Your assistant": whose it is, and that it
    /// costs you nothing (L4); "free" is lower case mid-line (L3).
    static func optionDetail(_ option: NativeCallTranslationState.Option, context: NativeCallScreenViewModel.Context) -> String {
        if option.isYours, option.producers.isEmpty {
            return UntranslatedL10n.screenNativeCallAgentPillYourAssistant
        }
        let owner = option.producerOwners.first.map { firstName($0, context: context) }
        switch (option.isPartial, owner) {
        case (true, let owner?): return UntranslatedL10n.screenNativeCallTranslatePartialBy(option.covered, option.needed, owner)
        case (true, nil): return UntranslatedL10n.screenNativeCallTranslatePartial(option.covered, option.needed)
        case (false, let owner?): return UntranslatedL10n.screenNativeCallTranslateFreeBy(owner)
        case (false, nil): return UntranslatedL10n.screenNativeCallTranslateFree
        }
    }

    /// A stopped track's line: what the capsule said, and its action.
    static var stoppedDetail: String {
        "\(UntranslatedL10n.screenNativeCallCapsuleStopped) · \(UntranslatedL10n.screenNativeCallCapsuleContinue)"
    }

    /// A person by their first name, as the board writes them ("Bohdan"); "you" never gets here.
    static func firstName(_ userID: String, context: NativeCallScreenViewModel.Context) -> String {
        let name = context.viewState.memberProfiles[userID]?.displayName ?? NativeCallFallbackName.make(mxid: userID)
        return name.split(separator: " ").first.map(String.init) ?? name
    }
}
