//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

/// The assistant's page shows its name on one line and its role under it, instead of the whole display name in two
/// heavy lines.
struct NativeCallAssistantTitleTests {
    @Test
    func theRoleAfterTheDotGoesUnderTheName() {
        let title = NativeCallAssistantTitle(displayName: "Alex Sample · assistant")
        #expect(title.name == "Alex Sample")
        #expect(title.role == "assistant")

        let russian = NativeCallAssistantTitle(displayName: "Мира Тестова · ассистент")
        #expect(russian.name == "Мира Тестова")
        #expect(russian.role == "ассистент")
    }

    @Test
    func aNameWithADotOfItsOwnSplitsAtTheLastOne() {
        let title = NativeCallAssistantTitle(displayName: "Studio · North · assistant")
        #expect(title.name == "Studio · North")
        #expect(title.role == "assistant")
    }

    @Test
    func aNameWithoutARoleStaysWhole() {
        #expect(NativeCallAssistantTitle(displayName: "Anna") == NativeCallAssistantTitle(name: "Anna", role: nil))
        #expect(NativeCallAssistantTitle(displayName: " · assistant").role == nil)
        #expect(NativeCallAssistantTitle(displayName: "Anna ·").name == "Anna ·")
        #expect(NativeCallAssistantTitle(displayName: "").name.isEmpty)
    }

    /// The assistant's page says only what its Aura can't: an error, a recording. Speaking, listening, waiting and the
    /// like are the ring's to show (operator, 2026-11-08); the interpreter's language is the avatar's badge (L12).
    @Test
    func thePageLineSaysOnlyWhatTheRingCant() {
        #expect(NativeCallAgentStatusCopy.assistantPageLine(.airing(.conversation)) == nil)
        #expect(NativeCallAgentStatusCopy.assistantPageLine(.idle(role: .conversation, languages: [])) == nil)
        #expect(NativeCallAgentStatusCopy.assistantPageLine(.idle(role: .waiting, languages: [])) == nil)
        #expect(NativeCallAgentStatusCopy.assistantPageLine(.idle(role: nil, languages: [])) == nil)

        #expect(NativeCallAgentStatusCopy.assistantPageLine(.failure(.deliveryFailed)) == UntranslatedL10n.screenNativeCallAgentBlockNotDelivered)
        #expect(NativeCallAgentStatusCopy.assistantPageLine(.idle(role: .recording, languages: []))
            == UntranslatedL10n.screenNativeCallAgentBlockRecording)

        // L12: no "my · neighbour" pair under the timer.
        #expect(NativeCallAgentStatusCopy.assistantPageLine(.airing(.translation(languages: ["uk", "es"]))) == nil)
        #expect(NativeCallAgentStatusCopy.assistantPageLine(.idle(role: nil, languages: ["uk", "es"])) == nil)
    }
}

extension NativeCallAssistantTitle {
    init(name: String, role: String?) {
        self.init(displayName: role.map { "\(name) · \($0)" } ?? name)
    }
}
