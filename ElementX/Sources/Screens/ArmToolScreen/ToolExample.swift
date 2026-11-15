//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359, items 12 and 20): what a kind of tool does, shown at the top of its form, in
// the shape the person meets it. Fixed sample text from the app's strings: never anyone's real messages, and nothing is
// sent anywhere.
//

import SwiftUI

struct ToolExample: Equatable {
    /// What a person gets when the tool fires, by what the backend does with it.
    enum Sample: Equatable {
        /// The agent's reply in the chat to a message it took. No reply until there's a language to give it in.
        case chat(message: String, reply: String?)
        /// The agent's message in the chat when the call has ended.
        case callSummary(SpiralCallSummary)
        /// The agent's voice message in the chat when the call has ended.
        case callRecording
    }
    
    let sample: Sample
    /// A word about the sample, drawn outside it: nothing in a sample is the app talking.
    let hint: String?
    
    init(kind: AgentToolKind, language: String) {
        switch kind {
        // Call translation has its own screen (ADR-0094 D9), with no example; its kind is only a translation here.
        case .translate, .liveTranslate:
            let translation = Translation(into: language)
            self.init(sample: .chat(message: translation.source, reply: translation.result), hint: translation.hint)
        case .simplify:
            self.init(sample: .chat(message: UntranslatedL10n.screenToolExampleMessage, reply: UntranslatedL10n.screenToolExampleSimplified))
        case .correct:
            self.init(sample: .chat(message: UntranslatedL10n.screenToolExampleTypos, reply: UntranslatedL10n.screenToolExampleCorrected))
        case .rephrase:
            self.init(sample: .chat(message: UntranslatedL10n.screenToolExampleMessage, reply: UntranslatedL10n.screenToolExampleRephrased),
                      hint: UntranslatedL10n.screenToolExampleInstructionPolite)
        case .custom:
            self.init(sample: .chat(message: UntranslatedL10n.screenToolExampleMessage, reply: UntranslatedL10n.screenToolExampleCustom),
                      hint: UntranslatedL10n.screenToolExampleInstructionTodo)
        case .summarize:
            self.init(sample: .chat(message: UntranslatedL10n.screenToolExampleMessage, reply: UntranslatedL10n.screenToolExampleSummary))
        case .callSummary:
            self.init(sample: .callSummary(SpiralCallSummary(text: UntranslatedL10n.screenToolExampleCallSummary,
                                                             decisionsTitle: UntranslatedL10n.screenToolExampleCallSummaryDecisionsTitle,
                                                             decisions: [UntranslatedL10n.screenToolExampleCallSummaryDecision],
                                                             actionItemsTitle: UntranslatedL10n.screenToolExampleCallSummaryActionItemsTitle,
                                                             actionItems: [UntranslatedL10n.screenToolExampleCallSummaryActionItem])))
        case .callRecording:
            self.init(sample: .callRecording)
        }
    }
    
    private init(sample: Sample, hint: String? = nil) {
        self.sample = sample
        self.hint = hint
    }
}

/// The greeting in the chosen language, as the app's strings have it. A language the app has no strings in gets the
/// tool's name as a hint instead: no sentence is made up for it.
private struct Translation {
    let source: String
    let result: String?
    let hint: String?
    
    init(into code: String) {
        let greeting = UntranslatedL10n.screenToolExampleGreeting
        guard !code.isEmpty else {
            self.init(source: greeting, result: nil, hint: UntranslatedL10n.screenArmToolLanguageChoose)
            return
        }
        guard let translated = Self.greeting(inLanguage: code) else {
            let language = TranslationLanguageDisplayName.localizedName(for: code)
            self.init(source: greeting, result: nil, hint: UntranslatedL10n.screenAgentToolsListTitleTranslate(language))
            return
        }
        // Into the person's own language: the sample has to start in another.
        let other = ["en", "es"].compactMap(Self.greeting(inLanguage:)).first { $0 != translated }
        self.init(source: translated == greeting ? other ?? greeting : greeting, result: translated, hint: nil)
    }
    
    private init(source: String, result: String?, hint: String?) {
        self.source = source
        self.result = result
        self.hint = hint
    }
    
    private static func greeting(inLanguage code: String) -> String? {
        let identifier = code.replacingOccurrences(of: "_", with: "-")
        let key = "screen_tool_example_greeting"
        // The catalogue says `zh-Hant` and `pt-PT`; the app's folders are `zh-Hant-TW` and `pt`.
        let nearest = Bundle.app.localizations.first { $0.hasPrefix(identifier) }
        for language in [identifier, nearest, identifier.components(separatedBy: "-").first].compactMap(\.self) {
            guard let bundle = Bundle.lprojBundle(for: language) else { continue }
            let greeting = NSLocalizedString(key, tableName: "Untranslated", bundle: bundle, comment: "")
            if greeting != key {
                return greeting
            }
        }
        return nil
    }
}
