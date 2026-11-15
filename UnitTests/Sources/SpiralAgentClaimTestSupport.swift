//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral

extension SpiralAgentStateReader.AgentClaim {
    /// A document v6 claim from the few facts a test cares about: one language is a `for_language` intent, two the
    /// pocket interpreter; `speakers` are the lanes it airs; `paused` is the Call translation cap's stop.
    static func make(languages: [String],
                     paused: Bool = false,
                     recording: Bool = false,
                     summaryArmed: Bool = false,
                     conversation: Bool = false,
                     style: SpiralAgentStateReader.TranslationStyle? = nil,
                     speakers: [String] = [],
                     owner: String? = nil,
                     lifecycle: SpiralAgentStateReader.Lifecycle = .live,
                     callGate: SpiralAgentStateReader.CallGate? = nil) -> SpiralAgentStateReader.AgentClaim {
        let isPocket = languages.count > 1
        let translation = languages.isEmpty
            ? SpiralAgentStateReader.TranslationClaim.none
            : SpiralAgentStateReader.TranslationClaim(isActive: !paused,
                                                      style: style ?? (isPocket ? .consecutive : .simultaneous),
                                                      source: .override,
                                                      forLanguage: isPocket ? nil : languages.first,
                                                      pocket: isPocket ? Array(languages.prefix(2)) : nil,
                                                      owner: owner,
                                                      lanes: paused ? [] : speakers.flatMap { speaker in languages.map { VoiceTranslationLane(speaker: speaker, language: $0) } },
                                                      stoppedReason: paused ? .translationPaused : nil)
        return .make(translation: translation,
                     recording: recording,
                     summaryArmed: summaryArmed,
                     conversation: conversation,
                     lifecycle: lifecycle,
                     callGate: callGate)
    }
}
