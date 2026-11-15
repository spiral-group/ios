//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (§ 5.56, question 412): the catalogue's shelves, search and sections, the post
// page's one running post, and your earlier posts, which are your generation threads.
//

import Combine
import Foundation
@testable import Spiral
import SwiftUI
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

    // MARK: - Shelves (question 373)

    /// A room of two wants a game for two first; any other room, a way to
    /// decide; the rest keep the catalogue's order.
    @Test(arguments: [(2, ["two", "record", "decide"]),
                      (3, ["decide", "record", "two"]),
                      (1, ["decide", "record", "two"])])
    func theFirstShelfFollowsTheRoom(people: Int, shelves: [String]) throws {
        let catalog = try Self.catalog(sections: ["record": ["a"], "two": ["b"], "decide": ["c"]], order: ["record", "two", "decide"])
        #expect(InteractivePostCatalogScreenViewState.shelves(of: catalog, peopleInRoom: people).map(\.id) == shelves)
    }

    @Test
    func unknownPeopleKeepTheCataloguesOrder() throws {
        let catalog = try Self.catalog(sections: ["record": ["a"], "two": ["b"]], order: ["record", "two"])
        #expect(InteractivePostCatalogScreenViewState.shelves(of: catalog, peopleInRoom: nil).map(\.id) == ["record", "two"])
    }

    /// The people counted first decide the order.
    @Test
    func aCountThatArrivesFirstOrdersTheShelves() async throws {
        let catalog = try Self.catalog(sections: ["decide": ["a"], "two": ["b"]], order: ["decide", "two"])
        let gate = Gate()
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [],
                                                              fetchCatalog: { _ in await gate.wait(); return .catalog(catalog) },
                                                              fetchArtifact: { _, _ in nil },
                                                              countPeople: { defer { gate.open() }; return 2 })
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalogLoad)) { $0 == .loaded }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.shelves.map(\.id) == ["two", "decide"])
    }

    /// A count that arrives after the catalogue doesn't move what is on screen.
    @Test
    func aCountThatArrivesLateDoesNotReshuffle() async throws {
        let catalog = try Self.catalog(sections: ["decide": ["a"], "two": ["b"]], order: ["decide", "two"])
        let gate = Gate()
        let read = Gate()
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [],
                                                              fetchCatalog: { _ in .catalog(catalog) },
                                                              fetchArtifact: { _, _ in nil },
                                                              countPeople: { await gate.wait(); read.open(); return 2 })
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalogLoad)) { $0 == .loaded }
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.shelves.map(\.id) == ["decide", "two"])

        gate.open()
        await read.wait()
        try await Task.sleep(for: .milliseconds(50))
        #expect(viewModel.context.viewState.shelves.map(\.id) == ["decide", "two"])
    }

    /// A card at rest has the catalogue's still before it has run (question
    /// 376); a card with none keeps the quiet grey.
    @Test
    func cardsAtRestShowTheCataloguesStills() async throws {
        let catalog = try Self.catalog(sections: ["two": ["a", "b"]], order: ["two"])
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [],
                                                              fetchCatalog: { _ in .catalog(catalog) },
                                                              fetchArtifact: { _, _ in nil },
                                                              fetchStill: { template, _ in template.id == "b" ? picture : nil })
        let stilled = deferFulfillment(viewModel.context.observe(\.viewState.catalogueStills)) { $0["b"] != nil }
        try await stilled.fulfill()

        #expect(viewModel.context.viewState.catalogueStills["b"] === picture)
        #expect(viewModel.context.viewState.catalogueStills["a"] == nil)
    }

    // MARK: - The one running post (question 412)

    /// The catalogue is stills only: opening it starts no web view.
    @Test
    func nothingRunsOnTheCatalogue() async throws {
        let world = try await World.open()
        try await world.waitUntil { world.state.artifacts.count == 5 }
        await world.settle()

        #expect(world.state.runningTemplateID == nil)
        #expect(world.hosts.made == 0)
    }

    /// A card pushes its page, which swipes through its section, and the page's post runs.
    @Test
    func aCardOpensItsPageAndThePostRuns() async throws {
        let world = try await World.open()
        let actions = world.recordActions()
        defer { actions.cancel() }
        try await world.waitUntil { world.state.artifacts["b"] != nil }

        try await world.openPage("b")

        #expect(actions.posts == 1)
        #expect(world.state.page == InteractivePostCatalogPage(section: world.state.shelves[0], currentID: "b"))
        #expect(world.hosts.mounted == ["tpl-b"])
    }

    /// A swipe hands the one post to the next page, and the last one keeps a picture of itself.
    @Test
    func aSwipeHandsThePostOnAndThePreviousOneFreezes() async throws {
        let world = try await World.opened()

        try await world.swipe(to: "b")

        #expect(world.state.page?.currentID == "b")
        #expect(world.state.page?.position == 2)
        #expect(world.state.stills["a"] != nil, "what the page left behind")
        #expect(world.hosts.mounted == ["tpl-a", "tpl-b"])
    }

    /// The page goes no further than its section: a post of another section, or
    /// the same post again, changes nothing.
    @Test
    func aSwipeStaysInItsSection() async throws {
        let world = try await World.opened()

        world.context.send(viewAction: .showPage(templateID: "d"))
        world.context.send(viewAction: .showPage(templateID: "a"))
        await world.settle()

        #expect(world.state.page?.currentID == "a")
        #expect(world.state.page?.position == 1)
        #expect(world.hosts.mounted == ["tpl-a"], "nothing restarted")
    }

    /// A post in two sections swipes through the one it was found in: the chosen chip's, else its first shelf's.
    @Test
    func aPageSwipesThroughTheSectionItWasFoundIn() async throws {
        let world = try await World.open()
        try await world.waitUntil { world.state.catalogLoad == .loaded }

        world.context.send(viewAction: .openPost(templateID: "c"))
        #expect(world.state.page?.section.id == "first")
        #expect(world.state.page?.position == 3)

        world.context.send(viewAction: .selectSection("second"))
        world.context.send(viewAction: .openPost(templateID: "c"))
        #expect(world.state.page?.section.id == "second")
        #expect(world.state.page?.position == 1)
    }

    /// However fast the swipes, there is one web view and one post in it.
    @Test
    func onlyOnePostIsEverLive() async throws {
        let world = try await World.opened()

        for id in ["b", "c", "b", "a", "c"] {
            world.context.send(viewAction: .showPage(templateID: id))
            await Task.yield()
        }
        try await world.waitUntilRunning("c")

        #expect(world.hosts.mostAtOnce == 1, "two posts ran at once")
        #expect(world.hosts.made == 1, "the same web view moves from page to page, for a while")
        #expect(world.hosts.mounted.last == "tpl-c")
    }

    /// A page whose files didn't come yet runs once they arrive.
    @Test
    func aPageBeforeItsFilesRunsWhenTheyArrive() async throws {
        let gate = Gate()
        let world = try await World.open(holding: "b", until: gate)
        try await world.waitUntil { world.state.catalogLoad == .loaded }

        world.context.send(viewAction: .openPost(templateID: "b"))
        world.context.send(viewAction: .screenAppeared(.post))
        await world.settle()
        #expect(world.state.runningTemplateID == nil)
        #expect(world.state.artifacts["b"] == nil, "Send stays disabled")

        gate.open()
        try await world.waitUntilRunning("b")
    }

    // MARK: - Going back, and what covers the page

    /// Back to the catalogue stops the post; the catalogue runs nothing.
    @Test
    func backStopsThePost() async throws {
        let world = try await World.opened()

        world.context.send(viewAction: .screenDisappeared(.post))
        try await world.waitUntilRunning(nil)

        #expect(world.hosts.live == 0)
    }

    /// A thread pushed over the page covers it: nothing runs under it, and the
    /// post comes back with the page.
    @Test
    func nothingRunsUnderAThread() async throws {
        let world = try await World.opened()
        try await world.swipe(to: "c")

        world.context.send(viewAction: .screenDisappeared(.post))
        try await world.waitUntilRunning(nil)
        #expect(world.hosts.live == 0)

        world.context.send(viewAction: .screenAppeared(.post))
        try await world.waitUntilRunning("c")
    }

    /// An appearance reported twice doesn't leave a web view running behind
    /// a screen that has gone: a count of them did, at 227 MB.
    @Test
    func aRepeatedAppearanceStillStopsThePost() async throws {
        let world = try await World.opened()

        world.context.send(viewAction: .screenAppeared(.post))
        world.context.send(viewAction: .screenDisappeared(.post))

        try await world.waitUntilRunning(nil)
        #expect(world.hosts.live == 0)
    }

    /// The sheet going takes the post with it, whatever the views reported.
    @Test
    func stoppingTheScreenStopsThePost() async throws {
        let world = try await World.opened()

        world.viewModel.stop()

        try await world.waitUntilRunning(nil)
        #expect(world.hosts.live == 0)
    }

    /// One web view is kept warm for a few pages, then replaced: kept for
    /// ever, its process only ever grows.
    @Test
    func aWebViewServesAFewPagesAndIsReplaced() async throws {
        let world = try await World.opened()

        for id in ["b", "c", "a", "b", "c", "a"] {
            try await world.swipe(to: id)
        }

        #expect(world.hosts.made == 2)
        #expect(world.hosts.mostAtOnce == 1)
    }

    /// A dismissal that comes while the last post is stopping has no next
    /// post to keep the web view warm for.
    @Test
    func aDismissalDuringAStopKeepsNoWebView() async throws {
        let world = try await World.opened()
        let unmounting = Gate()
        world.hosts.unmounting = unmounting

        world.context.send(viewAction: .showPage(templateID: "b"))
        try await world.waitUntil { world.hosts.unmountsWaiting == 1 }
        world.viewModel.stop()
        unmounting.open()
        try await world.waitUntilRunning(nil)
        await world.settle()

        #expect(world.hosts.destroyed == world.hosts.made, "a web view stayed parked after the sheet")
    }

    /// In the background nothing runs, so there is nothing for the system to
    /// kill and restart; the post comes back with the app.
    @Test
    func theBackgroundStopsThePostAndTheReturnResumesIt() async throws {
        let world = try await World.opened()
        try await world.swipe(to: "c")
        let center = NotificationCenter.default

        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        try await world.waitUntilRunning(nil)
        world.context.send(viewAction: .screenAppeared(.post))
        await world.settle()

        #expect(world.state.runningTemplateID == nil, "nothing starts in the background")
        #expect(world.hosts.live == 0)
        #expect(world.hosts.destroyed == world.hosts.made)
        #expect(world.state.stills["c"] != nil, "a picture taken on the way out")

        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        try await world.waitUntilRunning("c")
    }

    // MARK: - The page on screen (operator, 2026-11-15)

    /// The pager's first frame is on the section's first post, reported before the page's: until the page's post has
    /// been on screen, the pager goes back to it instead of making the first post the page's.
    @Test
    func aFirstFrameOnTheSectionsFirstPostScrollsBackToThePagesPost() {
        var hold = InteractivePostCatalogPagerHold()

        #expect(hold.postsOnScreen(["a"], pagePost: "b") == .scrollBack)
        #expect(hold.postsOnScreen([], pagePost: "b") == .none)
        #expect(hold.postsOnScreen(["b"], pagePost: "b") == .none)
        #expect(hold.hasShownPage)
    }

    /// Once the page's post has been on screen, the post the pager shows is the page's post, whatever moved it: a
    /// swipe, or VoiceOver, Full Keyboard Access or Switch Control, which may move it with no scroll phase.
    @Test
    func afterThePagesPostShowedThePagerIsTrusted() {
        var hold = InteractivePostCatalogPagerHold()
        _ = hold.postsOnScreen(["b"], pagePost: "b")

        #expect(hold.postsOnScreen(["c"], pagePost: "b") == .show("c"))
        #expect(hold.postsOnScreen(["c"], pagePost: "c") == .none)
    }

    /// A finger moving the pager always wins, even before the page's post showed, so a pager can't stick.
    @Test
    func aFingerWinsBeforeThePagesPostShowed() {
        var hold = InteractivePostCatalogPagerHold()

        hold.fingerMoved()

        #expect(hold.postsOnScreen(["a"], pagePost: "b") == .show("a"))
    }

    /// A card tapped while the catalogue's stills and files are still arriving opens its own post, and keeps it as
    /// they arrive.
    @Test
    func aCardTappedWhileTheCatalogueLoadsOpensItsOwnPost() async throws {
        let pager = try await Pager.open(tapping: "b")
        defer { pager.close() }
        try await pager.waitUntil { pager.postOnScreen == "b" }

        pager.finishLoading()
        try await pager.waitUntil { pager.hasLoaded }

        #expect(pager.postOnScreen == "b", "\(pager.diagnostics)")
        #expect(pager.state.page?.currentID == "b")
    }

    /// The shelves re-sorted after a page opened (the member count arriving late, DEBT L1) don't touch the page: it
    /// swipes through the section it was opened from, by id.
    @Test
    func shelvesReSortedAfterThePageOpenedLeaveItAlone() async throws {
        let world = try await World.opened()
        try await world.swipe(to: "b")
        let page = world.state.page

        world.viewModel.state.shelves.reverse()
        world.context.send(viewAction: .showPage(templateID: "c"))

        #expect(world.state.page?.section == page?.section)
        #expect(world.state.page?.currentID == "c")
        #expect(world.state.page?.position == 3)
    }

    // MARK: - Titles

    /// A title that has to wrap breaks at the space nearest its middle, so its two lines are about as long
    /// (question 412); a single word is left whole.
    @Test
    func aWrappedTitleBreaksAtTheSpaceNearestItsMiddle() {
        #expect(InteractivePostCatalogTitle.balanced("Интерактивные посты") == "Интерактивные\nпосты")
        #expect(InteractivePostCatalogTitle.balanced("Publicaciones de la sala") == "Publicaciones\nde la sala")
        #expect(InteractivePostCatalogTitle.balanced("Интерактивы") == "Интерактивы")
    }

    // MARK: - Full screen

    /// The running post asking for the whole screen (`ui.expand`) is heard, as in a chat, so the page opens its viewer
    /// (question 412): «Открой, чтобы рисовать» opened nothing. The next post, after a swipe, is heard too.
    @Test
    func theRunningPostAskingForTheScreenIsHeard() async throws {
        let world = try await World.opened()
        let preview = world.state.livePreview

        preview.instance?.onExpandRequested?()
        #expect(preview.expandRequests == 1)

        try await world.swipe(to: "b")
        preview.instance?.onExpandRequested?()
        #expect(preview.expandRequests == 2)
    }

    // MARK: - A post that won't run

    enum Breakage {
        case refuses
        case crashes
    }

    /// Each failure tried the post again with a fresh count, so a template
    /// that never runs made web views until the sheet closed.
    @Test(arguments: [Breakage.refuses, .crashes])
    func aPostThatWontRunIsTriedAFewTimes(breakage: Breakage) async throws {
        let world = try await World.opened()
        world.hosts.breaking["tpl-b"] = breakage
        let attempts = { world.hosts.mounted.filter { $0 == "tpl-b" }.count }

        world.context.send(viewAction: .showPage(templateID: "b"))
        try await world.waitUntil { attempts() > DraftPreview.retries && world.state.runningTemplateID == nil }
        await world.settle()
        await world.settle()

        #expect(attempts() == DraftPreview.retries + 1)
        #expect(world.state.runningTemplateID == nil)

        try await world.swipe(to: "c")
        #expect(world.hosts.mostAtOnce == 1, "the next post still runs, alone")
    }

    /// A cold shell is a long wait. A post left during it never ran, so it
    /// mustn't be mounted on the host the next post is waiting for.
    @Test
    func aPostLeftWhileTheShellWarmsNeverMounts() async throws {
        let shell = Gate()
        let world = try await World.open(shell: shell)
        try await world.waitUntil { world.state.artifacts["a"] != nil }
        world.context.send(viewAction: .openPost(templateID: "a"))
        world.context.send(viewAction: .screenAppeared(.post))
        try await world.waitUntil { world.hosts.waitingForShell == 1 }

        world.context.send(viewAction: .showPage(templateID: "b"))
        try await world.waitUntil { world.hosts.waitingForShell == 2 }
        shell.open()
        try await world.waitUntilRunning("b")
        await world.settle()

        #expect(world.hosts.mounted == ["tpl-b"])
        #expect(world.hosts.live == 1)
    }

    // MARK: - What the page offers

    /// A plain template is sent, and only someone with an agent changes it first.
    @Test(arguments: [(InteractivePostCatalogAssistant.available, true), (.none, false), (.settingUp, false), (.unknown, false)])
    func aPlainTemplateIsSent(assistant: InteractivePostCatalogAssistant, canChange: Bool) {
        #expect(Self.state(assistant: assistant).choiceAction(for: template()) == .publish(canChange: canChange))
    }

    /// A template that asks is filled in with the agent; without one, the page leads to one: create it, wait for it
    /// while it is set up, and never "create one" when the agents couldn't be read (question 412, decision 129).
    @Test(arguments: [(InteractivePostCatalogAssistant.available, InteractivePostCatalogChoiceAction.fillIn(ask: "Яке питання?")),
                      (.none, .createAgent),
                      (.settingUp, .agentSettingUp),
                      (.unknown, .agentUnknown)])
    func aTemplateThatAsksGoesToTheAgent(assistant: InteractivePostCatalogAssistant, action: InteractivePostCatalogChoiceAction) {
        let asks = template(asks: ["uk": "Яке питання?"])

        #expect(Self.state(assistant: assistant).choiceAction(for: asks) == action)
    }

    /// When the agents couldn't be read, Retry asks for them again, back on the same post (1.0.2 critic polish).
    @Test
    func retryAgentsAsksToReadThemAgainOnThePost() {
        let viewModel = InteractivePostCatalogScreenViewModel(previewState: Self.state(assistant: .unknown))
        var asked: [String] = []
        let cancellable = viewModel.actionsPublisher.sink { if case .retryAgents(let templateID) = $0 { asked.append(templateID) } }
        defer { cancellable.cancel() }

        viewModel.context.send(viewAction: .retryAgents(templateID: "invite"))

        #expect(asked == ["invite"])
    }

    /// «Create an agent» leaves for the Agents tab.
    @Test
    func createAgentAsksForTheAgentsTab() {
        let viewModel = InteractivePostCatalogScreenViewModel(previewState: Self.state(assistant: .none))
        var asked = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .showAgents = $0 { asked += 1 } }
        defer { cancellable.cancel() }

        viewModel.context.send(viewAction: .showAgents)

        #expect(asked == 1)
    }

    /// Send only says «Send»; VoiceOver names the chat. A catalogue link opens on the chat its picker chose first,
    /// so the page always has one to name (question 412, A1).
    @Test
    func sendNamesTheChatOnlyToVoiceOver() {
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Alice Example", catalogURL: Self.base, dms: [],
                                                              initialTemplateID: "dice",
                                                              fetchCatalog: { _ in .unavailable })

        #expect(viewModel.context.viewState.sendAccessibilityLabel == UntranslatedL10n.a11yInteractivePostSendToChat("Alice Example"))
        #expect(viewModel.context.viewState.sendAccessibilityLabel.contains("Alice Example"))
        #expect(!L10n.actionSend.contains("Alice Example"))
    }

    /// Only someone with an agent has Yours to open.
    @Test(arguments: [(InteractivePostCatalogAssistant.available, true), (.none, false), (.settingUp, false), (.unknown, false)])
    func yoursNeedsAnAgent(assistant: InteractivePostCatalogAssistant, hasYours: Bool) {
        #expect(Self.state(assistant: assistant).hasYours == hasYours)
    }

    // MARK: - Search and sections

    /// Typing filters by a template's title, its line and its section's name,
    /// whatever the case and accents, each template once.
    @Test(arguments: [("WHEEL", ["wheel"]), ("names", ["wheel"]), ("for two", ["chess", "wheel"]), ("cafe", ["dice"]), ("  dice ", ["dice"])])
    func searchFiltersAsItIsTyped(query: String, found: [String]) {
        var state = Self.searchState()
        state.bindings.searchQuery = query

        #expect(state.content == .grid(found.compactMap { state.catalog?.template($0) }))
    }

    /// A chosen section narrows a search to itself.
    @Test
    func aSearchStaysInTheChosenSection() {
        var state = Self.searchState()
        state.bindings.searchQuery = "e"
        state.bindings.sectionID = "two"

        #expect(state.content == .grid(["chess", "wheel"].compactMap { state.catalog?.template($0) }))
    }

    /// Nothing found offers the agent the very words typed.
    @Test
    func aSearchThatFindsNothingOffersTheAgent() {
        var state = Self.searchState()
        state.bindings.searchQuery = " karaoke "
        #expect(state.content == .noResults(query: "karaoke"))

        let viewModel = InteractivePostCatalogScreenViewModel(previewState: state)
        var described: String?
        let cancellable = viewModel.actionsPublisher.sink { action in
            if case .startNew(let description) = action { described = description }
        }
        defer { cancellable.cancel() }
        viewModel.context.send(viewAction: .startNew(description: "karaoke"))

        #expect(described == "karaoke")
    }

    /// The words go into the new thread as the person's first message there, and blank ones not at all.
    @Test
    func theAgentGetsTheWordsInTheThread() throws {
        let json = try #require(RoomFlowCoordinator.descriptionContent(" karaoke night ", threadRootEventID: "$root"))
        let content = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let relation = try #require(content["m.relates_to"] as? [String: Any])

        #expect(content["msgtype"] as? String == "m.text")
        #expect(content["body"] as? String == "karaoke night")
        #expect(relation["rel_type"] as? String == "m.thread")
        #expect(relation["event_id"] as? String == "$root")
        #expect(RoomFlowCoordinator.descriptionContent("  ", threadRootEventID: "$root") == nil)
    }

    /// A chip shows its section as a grid; «All» brings the shelves back.
    @Test
    func aSectionChipShowsItsSection() {
        let viewModel = InteractivePostCatalogScreenViewModel(previewState: Self.searchState())
        let context = viewModel.context
        #expect(context.viewState.content == .shelves(context.viewState.shelves))

        context.send(viewAction: .selectSection("decide"))
        #expect(context.viewState.content == .grid(["dice", "wheel"].compactMap { context.viewState.catalog?.template($0) }))

        context.send(viewAction: .selectSection(nil))
        #expect(context.viewState.content == .shelves(context.viewState.shelves))
    }

    // MARK: - The introduction

    /// The first opening starts with the introduction; finishing it is remembered, once.
    @Test
    func theIntroductionShowsOnceAndIsRemembered() {
        var seen = 0
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [],
                                                              hasSeenIntroduction: false,
                                                              introductionSeen: { seen += 1 },
                                                              fetchCatalog: { _ in .unavailable })
        #expect(!viewModel.context.viewState.hasSeenIntroduction)

        viewModel.context.send(viewAction: .finishIntroduction)

        #expect(viewModel.context.viewState.hasSeenIntroduction)
        #expect(seen == 1)
    }

    /// A link names a post: it goes there, and the introduction is still to come.
    @Test
    func aLinkSkipsTheIntroductionWithoutSpendingIt() {
        var seen = 0
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [],
                                                              initialTemplateID: "dice",
                                                              hasSeenIntroduction: false,
                                                              introductionSeen: { seen += 1 },
                                                              fetchCatalog: { _ in .unavailable })

        #expect(viewModel.context.viewState.hasSeenIntroduction)
        #expect(seen == 0)
    }

    // MARK: - Failure

    /// A failed read is no empty catalogue, and a retry reads again.
    @Test
    func aFailedIndexSaysSoAndRetries() async throws {
        let catalog = try Self.catalog(sections: ["decide": ["a"]], order: ["decide"])
        var answers: [SpiralAppCatalog.Fetched] = [.unavailable, .catalog(catalog)]
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [],
                                                              fetchCatalog: { _ in answers.removeFirst() },
                                                              fetchArtifact: { _, _ in nil })
        let failed = deferFulfillment(viewModel.context.observe(\.viewState.catalogLoad)) { $0 == .failed }
        try await failed.fulfill()
        #expect(viewModel.context.viewState.shelves.isEmpty)

        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalogLoad)) { $0 == .loaded }
        viewModel.context.send(viewAction: .retryCatalog)
        try await loaded.fulfill()
        #expect(viewModel.context.viewState.shelves.map(\.id) == ["decide"])
    }

    /// A newer catalogue format asks for an update and offers no retry (decision 96).
    @Test
    func aNewerIndexAsksForAnUpdate() async throws {
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [],
                                                              fetchCatalog: { _ in .newerFormat },
                                                              fetchArtifact: { _, _ in nil })
        let needsUpdate = deferFulfillment(viewModel.context.observe(\.viewState.catalogLoad)) { $0 == .needsNewerApp }
        try await needsUpdate.fulfill()
    }

    /// A failed read of the threads is not "nothing of yours yet".
    @Test
    func aFailedThreadReadIsNotAnEmptyList() async throws {
        let list = RoomThreadListServiceProxyMock(.init(paginationState: .idle(endReached: false),
                                                        paginateResult: .failure(.sdkError(ClientProxyMockError.generic))))
        let dm = JoinedRoomProxyMock(.init(id: "!dm:spiral.md"))
        dm.threadListServiceReturnValue = list
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: Self.base, dms: [dm],
                                                              fetchCatalog: { _ in .unavailable },
                                                              fetchArtifact: { _, _ in nil })

        let failed = deferFulfillment(viewModel.context.observe(\.viewState.threadsLoad)) { $0 == .failed }
        try await failed.fulfill()
    }

    // MARK: - A catalogue link (decision 111)

    private static let linkIndex = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice"]},{"id":"play","title":"Пограти","items":["quiz","chess"]}],"items":[{"id":"dice","title":"Кубик","description":"d6","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json"},{"id":"quiz","title":"Вікторина","description":"…","aspect":"4:3","source":"q","manifest":"m"},{"id":"chess","title":"Шахи","description":"…","aspect":"1:1","source":"c","manifest":"m"}]}"#

    /// The link's template opens on its own page over the catalogue, whatever shelf it is on.
    @Test
    func aLinksTemplateOpensItsPage() async throws {
        let base = try catalogue()
        try Self.linkIndex.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [], initialTemplateID: "chess")
        var posts = 0
        let cancellable = viewModel.actionsPublisher.sink { if case .showPost = $0 { posts += 1 } }
        defer { cancellable.cancel() }
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalog)) { $0 != nil }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.page?.currentID == "chess")
        #expect(viewModel.context.viewState.page?.section.id == "play")
        #expect(posts == 1)
    }

    /// An id the catalogue lacks opens the catalogue as any other time.
    @Test
    func anUnknownLinkOpensTheCatalogue() async throws {
        let base = try catalogue()
        try Self.linkIndex.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [], initialTemplateID: "nosuch")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalog)) { $0 != nil }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.page == nil)
    }

    /// A template the items list but no section holds is on no shelf.
    @Test
    func aLinkToATemplateInNoSectionOpensTheCatalogue() async throws {
        let base = try catalogue()
        let index = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice"]}],"items":[{"id":"dice","title":"Кубик","description":"d6","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json"},{"id":"loose","title":"Без розділу","description":"…","aspect":"1:1","source":"l","manifest":"m"}]}"#
        try index.write(to: base.appending(path: "index.json"), atomically: true, encoding: .utf8)
        let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [], initialTemplateID: "loose")
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.catalog)) { $0 != nil }
        try await loaded.fulfill()

        #expect(viewModel.context.viewState.page == nil)
    }

    /// The page runs the template, so every template's files are read once the
    /// catalogue is (§ 5.61). A catalogue from before § 5.61, with `row`, decodes too.
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

    // MARK: - Question 412: the «New» slider and a post's facts

    @Test
    func theNewSliderShowsEveryNewTemplateOverTheShelvesInTheCataloguesOrder() {
        var state = Self.searchState(newIDs: ["gone", "chess", "dice"])
        #expect(state.newCardTemplates.map(\.id) == ["chess", "dice"], "the catalogue's order, past an id it doesn't hold")
        #expect(state.isNew("chess") && state.isNew("dice"))
        #expect(!state.isNew("wheel"))

        state.bindings.sectionID = "decide"
        #expect(state.newCardTemplates.isEmpty, "a chosen section shows what was asked for")
        state.bindings.sectionID = nil
        state.bindings.searchQuery = "di"
        #expect(state.newCardTemplates.isEmpty, "so does a search")
        state.bindings.searchQuery = "  "
        #expect(state.newCardTemplates.map(\.id) == ["chess", "dice"], "a blank search is no search")

        state.shelves = state.shelves.filter { $0.id == "decide" }
        #expect(state.newCardTemplates.map(\.id) == ["dice"], "only what a shelf holds, as a page swipes through its shelf")
    }

    @Test
    func aCatalogueWithNothingNewHasNoNewSlider() {
        let state = Self.searchState()
        #expect(state.newCardTemplates.isEmpty)
        #expect(!state.isNew("dice"))
    }

    /// Players first, then the traits in the catalogue's order, three at most.
    @Test
    func aPostShowsPlayersThenItsTraitsThreeAtMost() {
        func template(players: SpiralAppTemplate.Players?, traits: [SpiralAppTemplate.Trait]) -> SpiralAppTemplate {
            SpiralAppTemplate(id: "rps", title: "rps", titles: nil, description: "", descriptions: nil, aspect: "1:1",
                              source: "rps.jsx", manifest: "rps.json", row: nil, asks: nil, runtime: nil, players: players, traits: traits)
        }
        let rps = InteractivePostCatalogFact.facts(of: template(players: .two, traits: [.sealed, .score]))
        #expect(rps.map(\.id) == ["players", "sealed", "score"])
        #expect(rps.map(\.text) == [UntranslatedL10n.screenInteractiveCatalogFactPlayersTwo,
                                    UntranslatedL10n.screenInteractiveCatalogFactSealedTwo,
                                    UntranslatedL10n.screenInteractiveCatalogFactScore])
        #expect(rps.map(\.symbol.rawValue) == ["person.2", "eye.slash", "trophy"])

        let group = InteractivePostCatalogFact.facts(of: template(players: .group, traits: [.sealed]))
        #expect(group.map(\.text) == [UntranslatedL10n.screenInteractiveCatalogFactPlayersGroup, UntranslatedL10n.screenInteractiveCatalogFactSealed],
                "hidden until everyone has chosen, not «both»")

        let many = InteractivePostCatalogFact.facts(of: template(players: .solo, traits: [.score, .live, .names]))
        #expect(many.map(\.id) == ["players", "score", "live"])

        let noPlayers = InteractivePostCatalogFact.facts(of: template(players: nil, traits: [.score, .live, .names]))
        #expect(noPlayers.map(\.id) == ["score", "live", "names"], "a catalogue without players still shows its traits")

        #expect(InteractivePostCatalogFact.facts(of: template(players: nil, traits: [])).isEmpty, "a catalogue packed before them: no facts")
    }

    /// Introduction C fans three posts with little text; a catalogue without one takes the next it holds.
    @Test
    func theIntroductionFansDotsTheWheelAndSeaBattle() throws {
        var state = Self.state(assistant: .available)
        state.shelves = [.init(id: "decide", title: "Decide", titles: nil, items: ["who-wheel", "dice"]),
                         .init(id: "two", title: "For two", titles: nil, items: ["dots", "sea-battle", "chess"])]
        #expect(state.introductionTemplateIDs == ["dots", "who-wheel", "sea-battle"])

        state.shelves = [.init(id: "decide", title: "Decide", titles: nil, items: ["who-wheel", "dice"]),
                         .init(id: "two", title: "For two", titles: nil, items: ["chess"])]
        #expect(state.introductionTemplateIDs == ["dice", "who-wheel", "chess"])

        state.shelves = []
        #expect(state.introductionTemplateIDs.isEmpty, "before the catalogue arrives: no stills, the fan keeps its size")
    }

    // MARK: - Helpers

    private static let base: URL = "https://spiral.md/catalog/"

    private static func state(assistant: InteractivePostCatalogAssistant) -> InteractivePostCatalogScreenViewState {
        InteractivePostCatalogScreenViewState(roomName: "Група", catalogURL: base, ownUserID: "@a:h", assistant: assistant, livePreview: DraftPreview())
    }

    /// Two sections sharing one template, with words to search for.
    private static func searchState(newIDs: [String] = []) -> InteractivePostCatalogScreenViewState {
        func template(_ id: String, _ title: String, _ description: String) -> SpiralAppTemplate {
            SpiralAppTemplate(id: id, title: title, titles: nil, description: description, descriptions: nil, aspect: "1:1",
                              source: "\(id).jsx", manifest: "\(id).json", row: nil, asks: nil, runtime: nil)
        }
        let catalog = SpiralAppCatalog(runtime: "1",
                                       sections: [.init(id: "decide", title: "Decide", titles: nil, items: ["dice", "wheel"]),
                                                  .init(id: "two", title: "For two", titles: nil, items: ["chess", "wheel"])],
                                       items: [template("dice", "Dice", "Who pays at the café"),
                                               template("wheel", "Wheel", "Stops on one of the names"),
                                               template("chess", "Chess", "The whole game")],
                                       newIDs: newIDs)
        var state = state(assistant: .available)
        state.catalog = catalog
        state.shelves = catalog.sections
        return state
    }

    private static func catalog(sections: [String: [String]], order: [String]) throws -> SpiralAppCatalog {
        let items = order.flatMap { sections[$0] ?? [] }.map {
            SpiralAppTemplate(id: $0, title: $0, titles: nil, description: "", descriptions: nil, aspect: "1:1",
                              source: "\($0).jsx", manifest: "\($0).json", row: nil, asks: nil, runtime: nil)
        }
        return SpiralAppCatalog(runtime: "1",
                                sections: order.map { .init(id: $0, title: $0, titles: nil, items: sections[$0] ?? []) },
                                items: items)
    }

    private static func artifact(_ id: String) -> SpiralAppArtifact? {
        let manifest = #"{"app_id":"tpl-\#(id)","runtime":"1","entry":"app.jsx","aspect":"1:1","state_channel":"matrix","capabilities":["app.context.read"],"limits":{"max_state_bytes":16384}}"#
        let packed = SpiralAppContainer.pack(manifestJSON: manifest, entry: "app.jsx", source: "export default () => null;")
        return SpiralAppArtifact.verified(packed: packed, claimedDigest: SpiralAppArtifact.digest(of: packed))
    }

    /// A screen on a real preview and live card, with only WebKit replaced.
    private struct World {
        let viewModel: InteractivePostCatalogScreenViewModel
        let hosts: Hosts

        var context: InteractivePostCatalogScreenViewModel.Context {
            viewModel.context
        }

        var state: InteractivePostCatalogScreenViewState {
            viewModel.context.viewState
        }

        /// On the first post's page, with it running.
        static func opened() async throws -> World {
            let world = try await open()
            try await world.waitUntil { world.state.artifacts["a"] != nil }
            try await world.openPage("a")
            return world
        }

        /// The catalogue on screen. `shell` holds every host's shell back, as a cold one is.
        static func open(holding heldID: String? = nil, until gate: Gate? = nil, shell: Gate? = nil) async throws -> World {
            let catalog = try catalog(sections: ["first": ["a", "b", "c"], "second": ["c", "d", "e"]], order: ["first", "second"])
            let hosts = Hosts()
            hosts.shell = shell
            let viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: base, dms: [],
                                                                  livePreview: DraftPreview { hosts.make() },
                                                                  fetchCatalog: { _ in .catalog(catalog) },
                                                                  fetchArtifact: { template, _ in
                                                                      if template.id == heldID { await gate?.wait() }
                                                                      return artifact(template.id)
                                                                  })
            viewModel.context.send(viewAction: .screenAppeared(.catalogue))
            return World(viewModel: viewModel, hosts: hosts)
        }

        /// A card tapped: the page pushed over the catalogue, the post running on it.
        func openPage(_ id: String) async throws {
            context.send(viewAction: .openPost(templateID: id))
            context.send(viewAction: .screenAppeared(.post))
            context.send(viewAction: .screenDisappeared(.catalogue))
            try await waitUntilRunning(id)
        }

        func swipe(to id: String) async throws {
            context.send(viewAction: .showPage(templateID: id))
            try await waitUntilRunning(id)
        }

        func waitUntilRunning(_ id: String?) async throws {
            for _ in 0..<500 {
                if state.runningTemplateID == id, id == nil || state.livePreview.isReady { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("\(id ?? "nothing") never ran; \(state.runningTemplateID ?? "nothing") did")
        }

        func waitUntil(_ condition: () -> Bool) async throws {
            for _ in 0..<500 {
                if condition() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("waited in vain")
        }

        /// Long enough for a change the two screens' turn could have started.
        func settle() async {
            try? await Task.sleep(for: .milliseconds(100))
        }

        func recordActions() -> ActionRecord {
            let record = ActionRecord()
            record.cancellable = viewModel.actionsPublisher.sink { action in
                if case .showPost = action { record.posts += 1 }
            }
            return record
        }
    }

    /// The post page as the room's catalogue pushes it, on a navigation stack in a window. Stills and files wait
    /// until `finishLoading()`; no post ever finishes starting, so the running one keeps its place on its page.
    @MainActor
    private final class Pager {
        let viewModel: InteractivePostCatalogScreenViewModel
        private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        private let stack = NavigationStackCoordinator()
        private let loading = MainGate()
        private let hosts = Hosts()

        var state: InteractivePostCatalogScreenViewState {
            viewModel.context.viewState
        }

        private init() throws {
            let catalog = try InteractivePostCatalogScreenViewModelTests.catalog(sections: ["record": ["a", "b", "c", "d", "e", "f", "g"], "two": ["h", "i"]],
                                                                                order: ["record", "two"])
            let picture = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
            hosts.shell = Gate()
            let loading = loading
            viewModel = InteractivePostCatalogScreenViewModel(roomName: "Група", catalogURL: InteractivePostCatalogScreenViewModelTests.base, dms: [],
                                                              livePreview: DraftPreview { [hosts] in hosts.make() },
                                                              fetchCatalog: { _ in .catalog(catalog) },
                                                              fetchArtifact: { template, _ in
                                                                  await loading.wait()
                                                                  return InteractivePostCatalogScreenViewModelTests.artifact(template.id)
                                                              },
                                                              fetchStill: { _, _ in
                                                                  await loading.wait()
                                                                  return picture
                                                              })
        }

        /// The catalogue up, its stills and files still on their way, and the card tapped.
        static func open(tapping templateID: String) async throws -> Pager {
            let pager = try Pager()
            pager.showStack()
            try await pager.waitUntil { pager.state.catalogLoad == .loaded }

            pager.viewModel.context.send(viewAction: .openPost(templateID: templateID))
            pager.stack.push(InteractivePostCatalogPostScreenCoordinator(viewModel: pager.viewModel), animated: false)
            try await pager.waitUntil { pager.pagerScrollView != nil }
            return pager
        }

        private func showStack() {
            stack.setRootCoordinator(BlankFormCoordinator())
            window.rootViewController = UIHostingController(rootView: stack.toPresentable())
            window.isHidden = false
        }

        func close() {
            viewModel.stop()
            window.isHidden = true
        }

        func finishLoading() {
            loading.open()
        }

        /// Every still and every post's files are in.
        var hasLoaded: Bool {
            state.catalogueStills.count == 9 && state.artifacts.count == 9
        }

        /// The section's post whose page fills the screen, read off where the pages are laid out in the pager.
        var postOnScreen: String? {
            window.layoutIfNeeded()
            guard let pager = pagerScrollView, pager.bounds.width > 0, let section = state.page?.section else { return nil }
            guard let page = pageOnScreen else { return nil }
            let index = Int((page.convert(page.bounds, to: pager).minX / pager.bounds.width).rounded())
            return section.items.indices.contains(index) ? section.items[index] : nil
        }

        /// The scroll view of the page that fills the screen.
        private var pageOnScreen: UIScrollView? {
            window.layoutIfNeeded()
            guard let pager = pagerScrollView else { return nil }
            return views(in: pager).dropFirst().compactMap { $0 as? UIScrollView }.first { page in
                !page.isHidden && abs(page.convert(page.bounds, to: window).minX) < pager.bounds.width / 2
            }
        }

        var diagnostics: String {
            "on screen \(postOnScreen ?? "none"), running \(state.runningTemplateID ?? "none"), offset \(pagerScrollView.map { "\($0.contentOffset.x) of \($0.contentSize.width)" } ?? "no pager")"
        }

        func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
            for _ in 0..<500 {
                window.layoutIfNeeded()
                if condition() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("waited in vain: \(diagnostics), loaded \(hasLoaded)", sourceLocation: sourceLocation)
        }

        private var pagerScrollView: UIScrollView? {
            views(in: window).lazy.compactMap { $0 as? UIScrollView }.first { $0.contentSize.width > $0.bounds.width * 1.5 }
        }

        private func views(in root: UIView) -> [UIView] {
            [root] + root.subviews.flatMap(views)
        }
    }

    /// A `Gate` for many waiters at once, each let go on the main actor.
    @MainActor
    private final class MainGate {
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting.removeAll()
        }

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    private final class ActionRecord {
        var posts = 0
        var cancellable: AnyCancellable?

        func cancel() {
            cancellable?.cancel()
        }
    }

    /// What `FakeHost`s did between them.
    private final class Hosts {
        private(set) var made = 0
        private(set) var destroyed = 0
        private(set) var live = 0
        private(set) var mostAtOnce = 0
        private(set) var mounted: [String] = []
        /// Holds every shell back until opened.
        var shell: Gate?
        fileprivate var waitingForShell = 0
        /// Holds every unmount back until opened.
        var unmounting: Gate?
        fileprivate var unmountsWaiting = 0
        /// What goes wrong with each app, by its id.
        var breaking: [String: Breakage] = [:]

        func make() -> SpiralAppHostProtocol {
            made += 1
            return FakeHost(hosts: self)
        }

        fileprivate func didMount(_ appID: String) {
            live += 1
            mostAtOnce = max(mostAtOnce, live)
            mounted.append(appID)
        }

        fileprivate func didUnmount() {
            live -= 1
        }

        fileprivate func didDestroy() {
            destroyed += 1
        }
    }

    /// A host that does everything but touch WebKit.
    private final class FakeHost: SpiralAppHostProtocol {
        let containerView = UIView(frame: .zero)
        var onContentProcessDied: (@MainActor () -> Void)?
        private let hosts: Hosts
        private var isMounted = false

        init(hosts: Hosts) {
            self.hosts = hosts
        }

        func bind(_ handler: @escaping SpiralAppMethodHandler) { }
        func push(_ message: [String: Any]) async { }

        func waitUntilReady() async {
            guard let shell = hosts.shell else { return }
            hosts.waitingForShell += 1
            await shell.wait()
        }

        func destroy() {
            if isMounted {
                isMounted = false
                hosts.didUnmount()
            }
            hosts.didDestroy()
        }

        func mount(_ mount: SpiralAppMount) async throws {
            let appID = mount.artifact.manifest.appID
            isMounted = true
            hosts.didMount(appID)
            // The time a real mount takes, so that a second one would overlap.
            await Task.yield()
            switch hosts.breaking[appID] {
            case .refuses:
                isMounted = false
                hosts.didUnmount()
                throw SpiralAppHostError.timedOut
            case .crashes:
                Task { self.onContentProcessDied?() }
            case nil:
                break
            }
        }

        func unmount() async {
            if let unmounting = hosts.unmounting {
                hosts.unmountsWaiting += 1
                await unmounting.wait()
            }
            guard isMounted else { return }
            isMounted = false
            hosts.didUnmount()
        }

        func takeSnapshot(_ completion: @escaping (UIImage?) -> Void) {
            completion(UIImage(systemName: "circle"))
        }

        func waitForPaint() async -> Bool {
            true
        }

        func waitForLayout(_ size: CGSize) async -> Bool {
            true
        }
    }

    /// Holds a closure back until the test lets it go. Deaf to cancellation,
    /// as WebKit's waits are, and without spinning on a cancelled task.
    private final class Gate {
        private var isOpen = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func open() {
            isOpen = true
            waiting.forEach { $0.resume() }
            waiting.removeAll()
        }

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiting.append($0) }
        }
    }
}
