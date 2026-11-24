//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Foundation
@testable import Spiral
import Testing

// AGENT-PLATFORM (Brief 0085, backend ADR-0094 rows 1–2 and 14): the catalog's exact codes and "As on the phone", the
// catalog kept for a day, and the chat's personal tool on the wire and on the device.

@MainActor
struct CallTranslationLanguageAndToolTests {
    private let roomID = "!room:example.org"
    private let catalog = ["en", "uk", "pt-BR", "pt-PT", "zh-Hans", "zh-Hant"]

    // MARK: - Codes (rows 1–2)

    @Test(arguments: [("uk_UA", "uk"), ("pt_BR", "pt-BR"), ("pt-PT", "pt-PT"), ("zh-Hans-CN", "zh-Hans"), ("zh-Hant_TW", "zh-Hant"),
                      ("en-GB", "en"), ("EN", "en"), ("pt", "pt-BR")])
    func asOnThePhoneIsTheClosestCatalogCode(locale: String, code: String) {
        #expect(NativeCallLanguageCode.closest(to: locale, in: catalog) == code)
    }

    @Test
    func aLanguageTheCatalogLacksHasNoCode() {
        #expect(NativeCallLanguageCode.closest(to: "ka_GE", in: catalog) == nil)
    }

    @Test
    func theSameSpokenLanguageIsTheBaseSubtag() {
        #expect(NativeCallLanguageCode.isSameSpokenLanguage("pt-BR", "pt-PT"))
        #expect(!NativeCallLanguageCode.isSameSpokenLanguage("uk", "ru"))
    }

    @Test
    func myLanguageIsTheChosenCodeElseThePhonesClosest() {
        let store = NativeCallMyLanguageStore(defaults: defaults()) { "pt_BR" }
        #expect(store.resolved(catalog: catalog) == "pt-BR")
        // No catalog read yet: no code at all (D1); the screens name the app's language meanwhile.
        #expect(store.resolved(catalog: []) == nil)
        #expect(store.displayLanguage == "pt")

        store.setChosen("zh-Hans")
        #expect(store.resolved(catalog: catalog) == "zh-Hans")
    }

    /// ADR-0094 D1: the app's language if the catalog has it, else the phone's, else absent — never a code outside
    /// the catalog, and never a chosen code the catalog no longer has.
    @Test
    func myLanguageIsAbsentWhenTheCatalogHasNoneOfThePhonesLanguages() {
        let unknown = NativeCallMyLanguageStore(defaults: defaults(), deviceLanguages: { ["ka-GE"] }, phoneLanguage: { "ka_GE" })
        #expect(unknown.resolved(catalog: catalog) == nil)
        #expect(unknown.phoneCode(catalog: catalog) == nil)

        let fallsBack = NativeCallMyLanguageStore(defaults: defaults(), deviceLanguages: { ["ka-GE", "uk-UA"] }, phoneLanguage: { "ka_GE" })
        #expect(fallsBack.resolved(catalog: catalog) == "uk")

        fallsBack.setChosen("ka")
        #expect(fallsBack.resolved(catalog: catalog) == "uk")
    }

    /// D1: your own assistant is never asked for a language outside the catalog.
    @Test
    func nothingIsProducedIntoALanguageOutsideTheCatalog() {
        var inputs = NativeCallTranslationState.Inputs(ownUserID: "@me:example.org", myLanguage: "ka")
        inputs.speakers = ["@me:example.org", "@john:example.org"]
        inputs.languages = ["@john:example.org": "en"]
        #expect(NativeCallTranslationState(inputs).productionParams == .forLanguage("ka"))

        inputs.canProduceMyLanguage = false
        #expect(NativeCallTranslationState(inputs).productionParams == nil)
    }

    #if DEBUG || SPIRAL_STAGING
    /// D1 in the call: with no catalog yet, the join carries no language and nothing is published; the catalog
    /// arriving publishes the closest code.
    @Test
    func myLanguageIsPublishedOnceTheCatalogIsKnown() async throws {
        let port = LateCatalogPort()
        let backend = NativeCallAssistantsLabBackend(cast: .onePerson, role: .moderator, latency: .none)
        let controller = NativeAgentCenterController(agentPlatformService: backend.makeService(),
                                                     roomID: NativeCallAssistantsLabBackend.roomID,
                                                     roomMemberMxids: { [] },
                                                     inviteAgent: { _ in true },
                                                     translationPort: port)
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@me:example.org:DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        rtcSession.joinEncryptMediaNotificationMediaLanguageReturnValue = .success(())
        rtcSession.transportCredentialsReturnValue = .failure(.roomInvalid)
        rtcSession.leaveReturnValue = .success(())
        rtcSession.membershipsReturnValue = .success([])
        let transport = NativeCallTransportMock()
        transport.underlyingEvents = Empty().eraseToAnyPublisher()
        transport.localIdentity = "@me:example.org:DEVICE"
        transport.remoteParticipants = []
        transport.remoteTracks = []
        let viewModel = NativeCallScreenViewModel(session: NativeCallSession(rtcSession: rtcSession,
                                                                             isRoomEncrypted: false,
                                                                             notifyRoom: false,
                                                                             configuration: .init(media: .audio, scope: .direct),
                                                                             transport: transport),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  agentCenter: controller,
                                                  appMediator: AppMediatorMock(.init()),
                                                  isVideoCall: false,
                                                  roomID: NativeCallAssistantsLabBackend.roomID,
                                                  roomName: "John",
                                                  myLanguageStore: NativeCallMyLanguageStore(defaults: defaults(), deviceLanguages: { ["uk-UA"] }, phoneLanguage: { "ka_GE" }),
                                                  languageCatalog: NativeCallLanguageCatalogCache(defaults: defaults(), now: Date.init))
        #expect(viewModel.context.viewState.myLanguageCode == nil)

        viewModel.start()
        for _ in 0..<300 where rtcSession.joinEncryptMediaNotificationMediaLanguageCallsCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(rtcSession.joinEncryptMediaNotificationMediaLanguageCallsCount == 1)
        #expect(rtcSession.joinEncryptMediaNotificationMediaLanguageReceivedArguments?.language == nil)
        #expect(port.published.isEmpty)

        port.catalog = NativeCallAssistantsLabBackend.catalog
        await controller.reload()
        for _ in 0..<300 where port.published.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.context.viewState.myLanguageCode == "uk")
        #expect(port.published == ["uk"])
    }
    #endif

    // MARK: - Search (question 403, L10)

    /// One rule for every language list: the row's name, the language's own name, the start of its code; case and
    /// diacritics don't count.
    @Test(arguments: [("нем", "de", "Немецкий"), ("НІМ", "de", "Німецька"), ("нім", "de", "Німецька"),
                      ("deutsch", "de", "German"), ("francais", "fr", "French"), ("FRANÇ", "fr", "Французский"),
                      ("de", "de", "Немецкий"), ("pt-br", "pt-BR", "Portuguese"), ("pt_BR", "pt-BR", "Portuguese"),
                      ("zh-h", "zh-Hans", "Chinese"), (" нім ", "de", "Німецька"), ("", "de", "German")])
    func aSearchFindsALanguage(query: String, code: String, shownName: String) {
        #expect(TranslationLanguageDisplayName.matches(query, code: code, shownName: shownName))
    }

    @Test(arguments: [("xyz", "de", "German"), ("ans", "zh-Hans", "Chinese"), ("французский", "de", "Немецкий")])
    func aSearchLeavesOtherLanguagesOut(query: String, code: String, shownName: String) {
        #expect(!TranslationLanguageDisplayName.matches(query, code: code, shownName: shownName))
    }

    @Test
    func theSheetsListKeepsItsOrderWhileSearching() {
        let codes = ["uk", "de", "fr", "en"]
        #expect(NativeCallTranslationCopy.languages(codes, matching: "deutsch") == ["de"])
        #expect(NativeCallTranslationCopy.languages(codes, matching: "") == codes)
        #expect(NativeCallTranslationCopy.languages(codes, matching: "qqq").isEmpty)
    }

    // MARK: - The catalog, kept for a day (row 2)

    @Test
    func theCatalogIsReadOnceADayAndAFailedReadKeepsTheLastOne() async {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let cache = NativeCallLanguageCatalogCache(defaults: defaults()) { now }
        var reads = 0
        let languages: [VoiceControlsCatalogLanguage] = [.init(code: "uk", label: "Ukrainian"), .init(code: "zh-Hans", label: "Chinese")]

        #expect(await cache.load { reads += 1; return .success(languages) } == languages)
        #expect(await cache.load { reads += 1; return .success([]) } == languages)
        #expect(reads == 1, "fresh for a day: not read again")

        now.addTimeInterval(NativeCallLanguageCatalogCache.lifetime + 1)
        #expect(await cache.load { reads += 1; return .failure(.unavailable("offline")) } == languages)
        #expect(reads == 2)
    }

    // MARK: - The chat's tool (row 14, A.5)

    @Test
    func turningTheFallbackOnArmsTheToolWithItsConcreteLanguage() async throws {
        let service = toolService(tools: [])
        let store = NativeCallTranslationToolStore(service: service, myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "uk" })

        #expect(await store.write(.init(isEnabled: true, language: "pt-BR", translatesIfNobodyDoes: true, agentID: "agent-1"), roomID: roomID))

        let arm = try #require(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedArguments)
        #expect(arm.params == .liveTranslate(language: "pt-BR"))
        #expect(arm.trigger == .onVoiceCall(speakerScope: .anyone))
        #expect(arm.replacesToolID == nil)
        #expect(store.myLanguageStore.listenLanguage(roomID: roomID) == "pt-BR")
    }

    /// Off removes the Tool; the listening language stays on the device only.
    @Test
    func turningTheFallbackOffRemovesTheToolAndKeepsListeningOnTheDevice() async throws {
        let service = toolService(tools: [Self.armed("uk")])
        let store = NativeCallTranslationToolStore(service: service, myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "uk" })

        #expect(await store.write(.init(isEnabled: true, language: "uk", translatesIfNobodyDoes: false, agentID: "agent-1"), roomID: roomID))

        #expect(service.disableToolAgentIDRoomIDToolIDReceivedArguments?.toolID == "tool-1")
        #expect(!service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDCalled)
        #expect(store.myLanguageStore.listenLanguage(roomID: roomID) == "uk")
        let read = try await store.read(roomID: roomID, agentID: "agent-1").get()
        #expect(read?.isEnabled == true)

        #expect(await store.write(.init(isEnabled: false, language: "uk", agentID: "agent-1"), roomID: roomID))
        #expect(store.myLanguageStore.listenLanguage(roomID: roomID) == nil)
    }

    /// A.5: a second arm is `tool-duplicate`; the store edits the one there with `replaces_tool_id`.
    @Test
    func aDuplicateIsAnEditOfTheToolAlreadyThere() async throws {
        let service = toolService(tools: [])
        var reads = 0
        service.fetchRoomToolsRoomIDClosure = { [roomID] _ in
            reads += 1
            return .success(RoomToolsView(roomID: roomID, agents: [Self.ownAgent(tools: reads > 1 ? [Self.armed("en")] : [])]))
        }
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDClosure = { _, _, _, _, replaces in
            replaces == nil ? .failure(.refused(.duplicate)) : .success(ControlSetResultView(status: .applied, actionLogID: "log"))
        }
        let store = NativeCallTranslationToolStore(service: service, myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "uk" })

        #expect(await store.write(.init(isEnabled: true, language: "uk", translatesIfNobodyDoes: true, agentID: "agent-1"), roomID: roomID))

        #expect(service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReceivedInvocations.map(\.replacesToolID) == [nil, "tool-1"])
    }

    /// A failed room read is no answer: nothing is written.
    @Test
    func anUnreadableRoomWritesNothing() async {
        let service = toolService(tools: [])
        service.fetchRoomToolsRoomIDReturnValue = .failure(.transport(underlying: URLError(.notConnectedToInternet)))
        let store = NativeCallTranslationToolStore(service: service, myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "uk" })

        #expect(await store.write(.init(isEnabled: true, language: "uk", translatesIfNobodyDoes: true, agentID: "agent-1"), roomID: roomID) == false)
        #expect(!service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDCalled)
    }

    /// The screen: never set up, it shows my language, explicitly; switching on stores that concrete code and arms.
    @Test
    func theScreenStoresMyLanguageAsAConcreteCode() async throws {
        let service = ToolServiceStub()
        let viewModel = CallTranslationToolScreenViewModel(service: service,
                                                           myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "pt_BR" },
                                                           cachedCatalog: catalog.map { .init(code: $0, label: $0) })
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.isLoading)) { !$0 }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.tool == NativeCallTranslationTool(language: "pt-BR"))

        let saved = deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }
        viewModel.context.send(viewAction: .setEnabled(true))
        try await saved.fulfill()

        #expect(service.stored.last == NativeCallTranslationTool(isEnabled: true, language: "pt-BR", translatesIfNobodyDoes: true))
        #expect(viewModel.context.viewState.tool.translatesIfNobodyDoes)
    }

    /// A refused change is put back and said.
    @Test
    func aRefusedChangeIsPutBack() async throws {
        let service = ToolServiceStub()
        service.isStoring = false
        let viewModel = CallTranslationToolScreenViewModel(service: service,
                                                           myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "uk" },
                                                           cachedCatalog: catalog.map { .init(code: $0, label: $0) })
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.isLoading)) { !$0 }
        try await loaded.fulfill()

        let failed = deferFulfillment(viewModel.context.observe(\.viewState.isSaveFailed)) { $0 }
        viewModel.context.send(viewAction: .setEnabled(true))
        try await failed.fulfill()

        #expect(!viewModel.context.viewState.tool.isEnabled)
    }

    /// A second change while the first is being stored isn't dropped: it shows at once and is stored right after.
    @Test
    func aChangeDuringASaveIsStoredAfterIt() async throws {
        let service = ToolServiceStub()
        let viewModel = CallTranslationToolScreenViewModel(service: service,
                                                           myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "uk" },
                                                           cachedCatalog: catalog.map { .init(code: $0, label: $0) })
        try await deferFulfillment(viewModel.context.observe(\.viewState.isLoading)) { !$0 }.fulfill()

        // Both on the main actor before the first store runs: the second meets the save under way.
        viewModel.context.send(viewAction: .setEnabled(true))
        #expect(viewModel.context.viewState.isSaving)
        viewModel.context.send(viewAction: .setTranslatesIfNobodyDoes(false))
        #expect(viewModel.context.viewState.tool.translatesIfNobodyDoes == false, "the second switch doesn't snap back")

        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()

        #expect(service.stored.count == 2)
        #expect(service.stored.last?.isEnabled == true)
        #expect(service.stored.last?.translatesIfNobodyDoes == false)
        #expect(viewModel.context.viewState.tool.translatesIfNobodyDoes == false)
        #expect(!viewModel.context.viewState.isSaveFailed)
    }

    /// A change made while the save reads the tool back isn't lost to that read: it is stored next, once.
    @Test
    func aChangeDuringTheReadBackIsStored() async throws {
        let service = ToolServiceStub()
        let viewModel = try await loadedToolScreen(service)

        service.holdsNextRead = true
        viewModel.context.send(viewAction: .setEnabled(true))
        try await Self.waitUntil { service.isReadHeld }
        #expect(service.stored.count == 1)
        viewModel.context.send(viewAction: .setTranslatesIfNobodyDoes(false))
        service.releaseRead()
        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()

        #expect(service.stored.count == 2)
        #expect(service.stored.last?.translatesIfNobodyDoes == false)
        #expect(viewModel.context.viewState.tool.translatesIfNobodyDoes == false, "the switch doesn't snap back")

        // Nothing stale waits: the next change is written once.
        viewModel.context.send(viewAction: .setTranslatesIfNobodyDoes(true))
        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()
        #expect(service.stored.count == 3)
    }

    /// A refused save puts back the tool before it, with the change that waited on it, and says so; nothing waits on.
    @Test
    func aRefusedSaveTakesTheWaitingChangeWithIt() async throws {
        let service = ToolServiceStub()
        service.isStoring = false
        let viewModel = try await loadedToolScreen(service)

        viewModel.context.send(viewAction: .setEnabled(true))
        viewModel.context.send(viewAction: .setTranslatesIfNobodyDoes(false))
        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()

        #expect(viewModel.context.viewState.isSaveFailed)
        #expect(viewModel.context.viewState.tool == NativeCallTranslationTool(language: "uk"))

        service.isStoring = true
        viewModel.context.send(viewAction: .setLanguage("en"))
        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()
        #expect(service.stored.count == 1, "the refused change didn't come back to be written")
    }

    /// Only the first switch-on chooses «translate if nobody does»: switched off and on again before the first save
    /// lands, the person's own choice since stays.
    @Test
    func aSecondSwitchOnKeepsThePersonsChoice() async throws {
        let service = ToolServiceStub()
        let viewModel = try await loadedToolScreen(service)

        viewModel.context.send(viewAction: .setEnabled(true))
        viewModel.context.send(viewAction: .setTranslatesIfNobodyDoes(false))
        viewModel.context.send(viewAction: .setEnabled(false))
        viewModel.context.send(viewAction: .setEnabled(true))
        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()

        #expect(service.stored.last == NativeCallTranslationTool(isEnabled: true, language: "uk", translatesIfNobodyDoes: false))
    }

    /// A first switch-on that was refused (offline) leaves nothing stored: the next switch-on is the first again and
    /// keeps the promise of the tool's name.
    @Test
    func aRefusedFirstSwitchOnLeavesTheNextOneFirst() async throws {
        let service = ToolServiceStub()
        service.isStoring = false
        let viewModel = try await loadedToolScreen(service)

        viewModel.context.send(viewAction: .setEnabled(true))
        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()
        #expect(viewModel.context.viewState.isSaveFailed)

        service.isStoring = true
        viewModel.context.send(viewAction: .setEnabled(true))
        try await deferFulfillment(viewModel.context.observe(\.viewState.isSaving)) { !$0 }.fulfill()

        #expect(service.stored.last == NativeCallTranslationTool(isEnabled: true, language: "uk", translatesIfNobodyDoes: true))
    }

    // MARK: - Helpers

    private func loadedToolScreen(_ service: ToolServiceStub) async throws -> CallTranslationToolScreenViewModel {
        let viewModel = CallTranslationToolScreenViewModel(service: service,
                                                           myLanguageStore: NativeCallMyLanguageStore(defaults: defaults()) { "uk" },
                                                           cachedCatalog: catalog.map { .init(code: $0, label: $0) })
        try await deferFulfillment(viewModel.context.observe(\.viewState.isLoading)) { !$0 }.fulfill()
        return viewModel
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    private func defaults() -> UserDefaults {
        let suite = "CallTranslationLanguageAndToolTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private func toolService(tools: [RoomToolView]) -> AgentPlatformServiceMock {
        let service = AgentPlatformServiceMock()
        service.fetchRoomToolsRoomIDReturnValue = .success(RoomToolsView(roomID: roomID, agents: [Self.ownAgent(tools: tools)]))
        service.armToolAgentIDRoomIDParamsTriggerReplacesToolIDReturnValue = .success(ControlSetResultView(status: .applied, actionLogID: "log"))
        service.disableToolAgentIDRoomIDToolIDReturnValue = .success(ControlSetResultView(status: .applied, actionLogID: "log"))
        return service
    }

    private static func ownAgent(tools: [RoomToolView]) -> RoomToolAgentEntry {
        RoomToolAgentEntry(agentID: "agent-1", matrixUserID: "@assistant-me:example.org", displayName: "My assistant",
                           ownerUserID: "@me:example.org", isMine: true, tools: tools)
    }

    private static func armed(_ language: String) -> RoomToolView {
        RoomToolView(toolID: "tool-1", toolKind: "live_translate", triggerKind: "on_voice_call", targetLanguage: language,
                     params: .liveTranslate(language: language), trigger: .onVoiceCall(speakerScope: .anyone),
                     safeSliceSalt: "0", appliesToViewer: .notApplicable)
    }
}

private final class ToolServiceStub: CallTranslationToolServiceProtocol {
    var tool: NativeCallTranslationTool?
    var isStoring = true
    /// Holds the next read until `releaseRead()`: a change can then land during a save's read-back.
    var holdsNextRead = false
    private(set) var stored: [NativeCallTranslationTool] = []
    private var heldRead: CheckedContinuation<Void, Never>?

    var isReadHeld: Bool {
        heldRead != nil
    }

    func releaseRead() {
        heldRead?.resume()
        heldRead = nil
    }

    func languages() async -> [VoiceControlsCatalogLanguage]? {
        nil
    }

    func translationTool() async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        if holdsNextRead {
            holdsNextRead = false
            await withCheckedContinuation { heldRead = $0 }
        }
        return .success(tool)
    }

    func storeTranslationTool(_ tool: NativeCallTranslationTool) async -> Bool {
        guard isStoring else { return false }
        stored.append(tool)
        self.tool = tool.isEnabled ? tool : nil
        return true
    }
}

#if DEBUG || SPIRAL_STAGING
/// The platform's catalog, read only once the test says it arrived.
@MainActor
private final class LateCatalogPort: NativeCallTranslationPortProtocol {
    var catalog: [VoiceControlsCatalogLanguage]?
    private(set) var published: [String] = []

    func languages() async -> [VoiceControlsCatalogLanguage]? {
        catalog
    }

    func participantLanguages(roomID: String) async -> [String: String]? {
        [:]
    }

    func publishMyLanguage(_ language: String, roomID: String) async -> Bool {
        published.append(language)
        return true
    }

    func tool(roomID: String) async -> Result<NativeCallTranslationTool?, NativeCallTranslationPortError> {
        .success(nil)
    }

    func setTool(_ tool: NativeCallTranslationTool, roomID: String) async -> Bool {
        false
    }
}
#endif
