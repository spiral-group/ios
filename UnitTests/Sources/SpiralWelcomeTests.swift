//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

/// 1.0.3 A3: the assistant's welcome greets the person by first name and offers starters until they write; without their
/// AI consent it offers the way to allow AI instead, since the assistant can't read them (decision 150).
@MainActor
struct SpiralWelcomeTests {
    @Test
    func theWelcomeGreetsByFirstName() throws {
        #expect(SpiralNotice.firstName(of: "Alice Smith") == "Alice")
        #expect(SpiralNotice.firstName(of: "  Оля  Коваль ") == "Оля")
        #expect(SpiralNotice.firstName(of: "李雷") == "李雷")

        let data = #"{"com.spiral.notice":{"kind":"welcome","owner_display_name":"Alice Smith","agent_display_name":"Alice's Assistant","behavior":"personal_assistant"}}"#
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: data))
        #expect(notice.plainText == UntranslatedL10n.noticeWelcomeTitle("Alice"))
        #expect(notice.isPersonalWelcome)
    }

    @Test
    func anotherAgentsWelcomeOffersNoStarters() throws {
        let data = #"{"com.spiral.notice":{"kind":"welcome","owner_display_name":"Alice","agent_display_name":"Sales","behavior":"sales"}}"#
        #expect(try !#require(SpiralNotice(msgtype: "com.spiral.notice", data: data)).isPersonalWelcome)
    }

    @Test
    func theStartersFollowTheConsent() {
        let granted = AIConsent(isGranted: true, currentVersion: "1", decidedVersion: "1")
        let declined = AIConsent(isGranted: false, currentVersion: "1", decidedVersion: "1")

        #expect(SpiralWelcomeExtras.decide(needsStarters: true, consent: .loaded(granted)) == .starters)
        #expect(SpiralWelcomeExtras.decide(needsStarters: true, consent: .loaded(declined)) == .allowAI)
        #expect(SpiralWelcomeExtras.decide(needsStarters: true, consent: .loading) == .none, "Nothing pops in and out while it's read.")
        #expect(SpiralWelcomeExtras.decide(needsStarters: true, consent: .failed(.serverError(status: 503))) == .starters,
                "A failed read is not a refusal: the assistant asks for consent itself if it needs to.")
        #expect(SpiralWelcomeExtras.decide(needsStarters: true, consent: nil) == .starters)
        #expect(SpiralWelcomeExtras.decide(needsStarters: false, consent: .loaded(granted)) == .none)
    }

    @Test
    func theWatchOffersAllowAIUntilThePersonAllowsIt() async throws {
        let (store, service) = Self.makeStore(isGranted: false)
        service.setAIConsentGrantedReturnValue = .success(AIConsent(isGranted: true, currentVersion: "1", decidedVersion: "1"))
        var extras: [SpiralWelcomeExtras] = []
        let watch = SpiralWelcomeWatch(store: store) { extras.append($0) }
        
        watch.update(welcomeSender: AgentProfileMock.assistant.matrixUserID, ownerHasWritten: false)
        try await Self.waitUntil { extras.last == .allowAI }
        
        // The person allows AI in Settings: the starters come.
        _ = await store.setAIConsent(granted: true)
        try await Self.waitUntil { extras.last == .starters }
        
        // They write: the starters go, and nothing more is read for the welcome.
        watch.update(welcomeSender: AgentProfileMock.assistant.matrixUserID, ownerHasWritten: true)
        #expect(extras.last == SpiralWelcomeExtras.none)
        #expect(!store.isShown(.aiConsent))
        #expect(!store.isShown(.spaces))
    }
    
    /// Anyone can post a notice: a welcome from someone else's assistant, or from a person, is a hello and nothing more.
    @Test(arguments: ["@assistant-bob:spiral.md", "@bob:spiral.md"])
    func onlyTheOwnAssistantsWelcomeOffersStarters(sender: String) async throws {
        let (store, _) = Self.makeStore(isGranted: true)
        var extras: [SpiralWelcomeExtras] = []
        let watch = SpiralWelcomeWatch(store: store) { extras.append($0) }
        
        watch.update(welcomeSender: sender, ownerHasWritten: false)
        await Self.settle(store)
        try await Task.sleep(for: .milliseconds(200))
        #expect(store.spaces != nil, "The person's agents were read.")
        #expect(extras.allSatisfy { $0 == .none })
        
        // The person's own assistant does get them.
        watch.update(welcomeSender: AgentProfileMock.assistant.matrixUserID, ownerHasWritten: false)
        try await Self.waitUntil { extras.last == .starters }
    }
    
    @Test
    func noStartersWithoutTheAgentPlatform() {
        var extras: [SpiralWelcomeExtras] = []
        let watch = SpiralWelcomeWatch(store: nil) { extras.append($0) }
        watch.update(welcomeSender: AgentProfileMock.assistant.matrixUserID, ownerHasWritten: false)
        #expect(extras == [.none])
    }
    
    @Test
    func aSentStarterHidesTheStartersBeforeTheMessageShows() async throws {
        let (store, _) = Self.makeStore(isGranted: true)
        var extras: [SpiralWelcomeExtras] = []
        let watch = SpiralWelcomeWatch(store: store) { extras.append($0) }
        watch.update(welcomeSender: AgentProfileMock.assistant.matrixUserID, ownerHasWritten: false)
        try await Self.waitUntil { extras.last == .starters }
        
        watch.noteStarterSent()
        // The timeline updates before the message's echo is in it.
        watch.update(welcomeSender: AgentProfileMock.assistant.matrixUserID, ownerHasWritten: false)
        
        #expect(extras.last == SpiralWelcomeExtras.none)
    }
    
    // MARK: - Helpers

    private static func makeStore(isGranted: Bool) -> (AgentsStore, AgentPlatformServiceMock) {
        let userSession = UserSessionMock(.init())
        let service = AgentProfileMock.configure(userSession)
        service.fetchAIConsentReturnValue = .success(AIConsent(isGranted: isGranted, currentVersion: "1", decidedVersion: "1"))
        return (userSession.agentsStore!, service) // swiftlint:disable:this force_unwrapping
    }
    
    private static func settle(_ store: AgentsStore) async {
        for task in store.readTasks.values {
            await task.value
        }
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
