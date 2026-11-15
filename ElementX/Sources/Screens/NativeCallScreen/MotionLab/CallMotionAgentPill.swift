//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 383): the agent pill in the call-motion lab. The call's own pill
// (`NativeCallAgentBlock`, the Halo the operator picked) with every content of variant B of
// `DESIGNS/0083-call-motion/pill-audit.md`: who at rest, what it does when it does something, nothing the screen already
// says.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Foundation

enum CallMotionAgentPill {
    /// Every content of the call's pill, variant B.
    enum Case: String, CaseIterable, Identifiable {
        case yours = "Yours, at rest"
        case someoneElses = "Someone else's"
        case speaking = "Speaking (the Halo)"
        case listening = "Listening"
        case translating = "Translating"
        case translatingMore = "Translating, 3 languages"
        case paused = "Translation paused"
        case original = "Original voice"
        case notes = "Taking notes"
        case summaryFailed = "Summary not sent"
        case recordingFailed = "Recording not saved"
        case leaving = "Leaving"
        case recording = "Recording (REC says it)"
        case waiting = "Reconnecting (the header says it)"
        case twoAgents = "Two agents"
        case threeAgents = "Three agents"

        var id: Self {
            self
        }

        func state(agentUserID: String) -> NativeCallAgentBlockState {
            let own = "Alex Sample · assistant"
            let rest = NativeCallAgentEvent.idle(role: nil, languages: [])
            switch self {
            case .yours: return .init(name: own, event: rest, agentUserID: agentUserID, isOwn: true)
            case .someoneElses: return .init(name: "Mira Testova · assistant", event: rest, agentUserID: agentUserID)
            case .speaking: return .init(name: own, event: .airing(.conversation), agentUserID: agentUserID, isOwn: true)
            case .listening: return .init(name: own, event: .idle(role: .conversation, languages: []), agentUserID: agentUserID, isOwn: true)
            case .translating: return .init(name: own, event: .airing(.translation(languages: ["en", "de"])), agentUserID: agentUserID, isOwn: true)
            case .translatingMore: return .init(name: own, event: .idle(role: nil, languages: ["uk", "en", "de"]), agentUserID: agentUserID, isOwn: true)
            case .paused: return .init(name: own, event: .paused, agentUserID: agentUserID, isOwn: true)
            case .original: return .init(name: own, event: .original, agentUserID: agentUserID, isOwn: true)
            case .notes:
                return .init(name: own, event: .idle(role: .summary, languages: []), agentUserID: agentUserID, isOwn: true, isTakingNotes: true)
            case .summaryFailed:
                return .init(name: own, event: .failure(.deliveryFailed), agentUserID: agentUserID, isOwn: true, failedDelivery: .summary)
            case .recordingFailed:
                return .init(name: own, event: .failure(.deliveryFailed), agentUserID: agentUserID, isOwn: true, failedDelivery: .recording)
            case .leaving: return .init(name: own, event: rest, agentUserID: agentUserID, isOwn: true, isLeaving: true)
            case .recording: return .init(name: own, event: .idle(role: .recording, languages: []), agentUserID: agentUserID, isOwn: true)
            case .waiting: return .init(name: own, event: .idle(role: .waiting, languages: []), agentUserID: agentUserID, isOwn: true)
            case .twoAgents:
                return .init(name: own, event: rest, agentUserID: agentUserID, isOwn: true, otherAgentUserIDs: ["@assistant-mira:example.org"])
            case .threeAgents:
                return .init(name: own, event: rest, agentUserID: agentUserID, isOwn: true,
                             otherAgentUserIDs: ["@assistant-mira:example.org", "@assistant-oleh:example.org"])
            }
        }
    }
}

#endif
