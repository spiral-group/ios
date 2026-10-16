//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (§ 5.56): your earlier posts are your generation threads.
//

@testable import ElementX
import Foundation
import Testing

@MainActor
struct InteractivePostCatalogScreenViewModelTests {
    @Test
    func aRequestRootNamesTheRoomItWasMadeFor() {
        let root = UntranslatedL10n.screenRoomInteractivePostRequestBody("Група")

        #expect(InteractivePostCatalogScreenViewModel.madeForRoomName(inRootText: root) == "Група")
        #expect(InteractivePostCatalogScreenViewModel.madeForRoomName(inRootText: "emmm: " + root) == "Група",
                "the thread list prefixes the sender")
        #expect(InteractivePostCatalogScreenViewModel.madeForRoomName(inRootText: "Табло гри «бета»") == nil,
                "any text with guillemets is not a request")
    }

    /// A thread begun in one language is still found after the app changes
    /// to another: the root's text is whatever language it was written in.
    @Test
    func aRootIsRecognisedInEveryShippedLanguage() {
        for root in ["Interactive post for «Група»",
                     "Інтерактивний пост для «Група»",
                     "Интерактивный пост для «Група»",
                     "Вы: Интерактивный пост для «Група»"] {
            #expect(InteractivePostCatalogScreenViewModel.madeForRoomName(inRootText: root) == "Група", "\(root)")
        }
        #expect(InteractivePostCatalogScreenViewModel.requestBodyTemplates.count >= 3,
                "en, uk and ru each ship the request body")
    }

    @Test
    func aThreadWithADraftIsListedByTheDraftsTitle() throws {
        let sender = TimelineItemSender(id: "@emmm:spiral.md")
        let thread = RoomThreadListItem(id: "$root",
                                        rootMessageDetails: .init(sender: sender,
                                                                  timestamp: .distantPast,
                                                                  message: AttributedString(UntranslatedL10n.screenRoomInteractivePostRequestBody("Група"))),
                                        latestMessageDetails: .init(sender: sender,
                                                                    timestamp: .now,
                                                                    message: AttributedString("Draft - Табло гри"),
                                                                    interactiveDraftTitle: "Табло гри"),
                                        numberOfReplies: 4)

        let item = try #require(InteractivePostCatalogScreenViewModel.item(from: thread, dmRoomID: "!dm:spiral.md"))
        #expect(item.title == "Табло гри")
        #expect(item.madeForRoomName == "Група")
        #expect(item.dmRoomID == "!dm:spiral.md")
    }

    @Test
    func anOrdinaryThreadIsNotAPost() {
        let sender = TimelineItemSender(id: "@emmm:spiral.md")
        let thread = RoomThreadListItem(id: "$root",
                                        rootMessageDetails: .init(sender: sender, timestamp: .now, message: AttributedString("як справи?")),
                                        latestMessageDetails: nil,
                                        numberOfReplies: 1)

        #expect(InteractivePostCatalogScreenViewModel.item(from: thread, dmRoomID: "!dm:spiral.md") == nil)
    }

    // MARK: - The preview (§ 5.60)

    /// A catalogue on disk, as Caddy serves it: one template's files.
    private func catalogue() throws -> URL {
        let base = URL.temporaryDirectory.appending(path: "catalog-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(at: base.appending(path: "dice"), withIntermediateDirectories: true)
        try "export default () => null;".write(to: base.appending(path: "dice/app.jsx"), atomically: true, encoding: .utf8)
        let manifest = #"{"app_id":"tpl-dice","runtime":"1","entry":"app.jsx","aspect":"1:1","state_channel":"matrix","capabilities":["app.context.read","members.basic.read"],"limits":{"max_state_bytes":16384}}"#
        try manifest.write(to: base.appending(path: "dice/manifest.json"), atomically: true, encoding: .utf8)
        return base
    }

    private func template(asks: [String: String]? = nil) -> SpiralAppTemplate {
        SpiralAppTemplate(id: "dice", title: "Кубик", titles: nil, description: "Кидок d6", descriptions: nil,
                          aspect: "1:1", source: "dice/app.jsx", manifest: "dice/manifest.json", row: nil,
                          asks: asks, runtime: nil)
    }

    /// The carousel: the chosen section's templates in the catalogue's
    /// order, «Describe a new one» last; the first card is current until
    /// the carousel moves; a section chip resets it (§ 5.63).
    @Test
    func theCarouselFollowsTheSectionAndRestsOnTheFirstCard() throws {
        let json = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice","poll"]},{"id":"play","title":"Пограти","items":["chess"]}],"items":[{"id":"dice","title":"Кубик","description":"d6","aspect":"1:1","source":"d","manifest":"m"},{"id":"poll","title":"Голосування","description":"…","aspect":"4:3","source":"p","manifest":"m","asks":{"uk":"Яке питання?"}},{"id":"chess","title":"Шахи","description":"…","aspect":"1:1","source":"c","manifest":"m"}]}"#
        let catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(json.utf8))
        var state = InteractivePostCatalogScreenViewState(roomName: "Група", catalogURL: URL.temporaryDirectory, ownUserID: "@a:h", loadMembers: { [:] })
        state.catalog = catalog

        #expect(state.cards.map(\.id) == ["dice", "poll", "chess", "describe-new"])
        #expect(state.currentCard?.template?.id == "dice", "the first, until the carousel moves")
        let chess = try #require(catalog.template("chess"))
        #expect(state.sectionTitle(of: chess) == "Пограти")

        state.bindings.currentCardID = "poll"
        #expect(state.currentCard?.template?.localizedAsk != nil, "the action under the card follows it")

        state.bindings.section = "play"
        state.bindings.currentCardID = nil
        #expect(state.cards.map(\.id) == ["chess", "describe-new"])
        #expect(state.currentCard?.template?.id == "chess")

        state.bindings.currentCardID = "describe-new"
        #expect(state.currentCard?.template == nil, "nothing to publish under «Describe a new one»")
    }

    /// A section chip puts the carousel on the section's FIRST card and
    /// rebuilds it, so it opens there rather than at the old offset — also
    /// when the chip tapped is the one already on (§ 5.80). The actions go
    /// out as they are (no dialog in between; § 5.63).
    @Test
    func aChipOpensItsSectionAtTheFirstCardAndActionsGoStraightOut() async throws {
        let base = try catalogue()
        let index = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice"]},{"id":"play","title":"Пограти","items":["quiz","chess"]}],"items":[{"id":"dice","title":"Кубик","description":"d6","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json"},{"id":"quiz","title":"Вікторина","description":"…","aspect":"4:3","source":"q","manifest":"m"},{"id":"chess","title":"Шахи","description":"…","aspect":"1:1","source":"c","manifest":"m"}]}"#
        try index.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [])
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalog)) { $0 != nil }
        try await loaded.fulfill()

        var actions: [InteractivePostCatalogScreenViewModelAction] = []
        let cancellable = viewModel.actionsPublisher.sink { actions.append($0) }
        defer { cancellable.cancel() }

        viewModel.context.currentCardID = "chess"
        viewModel.context.send(viewAction: .selectSection("play"))
        #expect(viewModel.context.viewState.bindings.section == "play")
        #expect(viewModel.context.viewState.bindings.currentCardID == "quiz", "the section's first card, not where the carousel was")
        #expect(viewModel.context.viewState.carouselGeneration == 1)

        viewModel.context.currentCardID = "chess"
        viewModel.context.send(viewAction: .selectSection("play"))
        #expect(viewModel.context.viewState.bindings.currentCardID == "quiz", "the chip already on goes back to the start too")
        #expect(viewModel.context.viewState.carouselGeneration == 2)

        viewModel.context.send(viewAction: .publishTemplate(template()))
        viewModel.context.send(viewAction: .showAllThreads)
        #expect(actions.count == 2)
        guard case .publishTemplate(let published) = actions[0], case .showAllThreads = actions[1] else {
            Issue.record("expected publish, then all threads")
            return
        }
        #expect(published.id == "dice")
    }

    // MARK: - A catalogue link (decision 111)

    private static let linkIndex = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice"]},{"id":"play","title":"Пограти","items":["quiz","chess"]}],"items":[{"id":"dice","title":"Кубик","description":"d6","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json"},{"id":"quiz","title":"Вікторина","description":"…","aspect":"4:3","source":"q","manifest":"m"},{"id":"chess","title":"Шахи","description":"…","aspect":"1:1","source":"c","manifest":"m"}]}"#

    /// The link's template is the card the catalogue opens on, whatever
    /// section it is in, and the carousel is rebuilt to start there.
    @Test
    func aLinksTemplateIsTheCardTheCatalogueOpensOn() async throws {
        let base = try catalogue()
        try Self.linkIndex.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [], initialTemplateID: "chess")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalog)) { $0 != nil }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.bindings.section == nil)
        #expect(viewModel.context.viewState.bindings.currentCardID == "chess")
        #expect(viewModel.context.viewState.currentCard?.template?.id == "chess")
        #expect(viewModel.context.viewState.carouselGeneration == 1)
    }

    /// An id the catalogue lacks leaves the carousel where it would be.
    @Test
    func anUnknownLinkRestsOnTheFirstCard() async throws {
        let base = try catalogue()
        try Self.linkIndex.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [], initialTemplateID: "nosuch")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalog)) { $0 != nil }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.bindings.currentCardID == nil)
        #expect(viewModel.context.viewState.currentCard?.template?.id == "dice")
        #expect(viewModel.context.viewState.carouselGeneration == 0)
    }

    /// A template the items list but no section holds is no card: the link
    /// rests on the first card rather than on a card the carousel lacks.
    @Test
    func aLinkToATemplateInNoSectionRestsOnTheFirstCard() async throws {
        let base = try catalogue()
        let index = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice"]}],"items":[{"id":"dice","title":"Кубик","description":"d6","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json"},{"id":"loose","title":"Без розділу","description":"…","aspect":"1:1","source":"l","manifest":"m"}]}"#
        try index.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [], initialTemplateID: "loose")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalog)) { $0 != nil }
        try await loaded.fulfill()
        
        #expect(viewModel.context.viewState.bindings.currentCardID == nil)
        #expect(viewModel.context.viewState.currentCard?.template?.id == "dice")
        #expect(viewModel.context.viewState.carouselGeneration == 0)
    }
    
    /// Without an agent (decision 129) the carousel is the templates alone:
    /// «Describe a new one» needs an agent.
    @Test
    func withoutAnAssistantTheCarouselIsTheTemplatesAlone() throws {
        var state = InteractivePostCatalogScreenViewState(roomName: "Група", catalogURL: URL.temporaryDirectory, ownUserID: "@a:h", loadMembers: { [:] }, assistant: .none)
        #expect(state.cards.isEmpty)
        state.catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(Self.linkIndex.utf8))
        #expect(state.cards.map(\.id) == ["dice", "quiz", "chess"])
    }

    /// «Yours» on the main screen: three, the named ones first.
    @Test
    func yoursShowsThreeNamedFirst() {
        func thread(_ id: String, title: String?) -> InteractivePostThreadItem {
            InteractivePostThreadItem(id: id, dmRoomID: "!dm", madeForRoomName: "Група", lastActivity: .now, title: title, lastMessage: nil, replies: 1)
        }
        var state = InteractivePostCatalogScreenViewState(roomName: "Група", catalogURL: URL.temporaryDirectory, ownUserID: "@a:h", loadMembers: { [:] })
        state.threads = [thread("a", title: nil), thread("b", title: "Кубик"), thread("c", title: nil), thread("d", title: "Табло"), thread("e", title: nil)]
        #expect(state.recentThreads.map(\.id) == ["b", "d", "a"])
    }

    /// The catalogue's rows run the templates, so every template's files are
    /// read once the catalogue is, and the preview of one opens at once
    /// (§ 5.61). A catalogue from before § 5.61, with `row`, decodes too.
    @Test
    func theCatalogueBringsEveryTemplatesFilesWithIt() async throws {
        let base = try catalogue()
        let index = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice"]}],"items":[{"id":"dice","title":"Кубик","description":"Кидок d6","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json","row":"dice/row.png"}]}"#
        try index.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [])

        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.artifacts)) { $0["dice"] != nil }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.catalog?.items.count == 1)
        #expect(viewModel.context.viewState.artifacts["dice"]?.manifest.appID == "tpl-dice")
    }

    /// The card shown and its two neighbours run, whichever cards the
    /// carousel happened to build first (§ 5.80): a first-come budget gave
    /// the slots to cards out of sight and left the middle one a picture.
    @Test
    func theCardShownAndItsNeighboursRun() throws {
        let json = #"{"version":1,"runtime":"1","sections":[{"id":"all","title":"Усі","items":["a","b","c","d","e"]}],"items":[{"id":"a","title":"A","description":"","aspect":"1:1","source":"a","manifest":"m"},{"id":"b","title":"B","description":"","aspect":"1:1","source":"b","manifest":"m"},{"id":"c","title":"C","description":"","aspect":"1:1","source":"c","manifest":"m"},{"id":"d","title":"D","description":"","aspect":"1:1","source":"d","manifest":"m"},{"id":"e","title":"E","description":"","aspect":"1:1","source":"e","manifest":"m"}]}"#
        var state = InteractivePostCatalogScreenViewState(roomName: "Група", catalogURL: URL.temporaryDirectory, ownUserID: "@a:h", loadMembers: { [:] })
        state.catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(json.utf8))
        func running() -> [String] {
            state.cards.filter { state.distance(of: $0) <= InteractivePostCatalogTemplateCell.liveReach }.map(\.id)
        }

        #expect(running() == ["a", "b"], "at the start: the first card and the one after it")
        state.bindings.currentCardID = "c"
        #expect(running() == ["b", "c", "d"])
        state.bindings.currentCardID = "describe-new"
        #expect(running() == ["e", "describe-new"], "at the end: the last template and «Describe a new one»")
    }
}
