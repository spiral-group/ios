//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (§ 5.56, question 412 concept G): the catalogue's sections
// and search, the post page with its one running post, and your earlier posts,
// which are your generation threads. No store of their own: the DM's thread
// list (MSC3856) is read, the threads whose root is an Interactive Post
// request kept, newest first.
//

import Combine
import SwiftUI

typealias InteractivePostCatalogScreenViewModelType = StateStoreViewModelV2<InteractivePostCatalogScreenViewState, InteractivePostCatalogScreenViewAction>

class InteractivePostCatalogScreenViewModel: InteractivePostCatalogScreenViewModelType, InteractivePostCatalogScreenViewModelProtocol {
    private let actionsSubject: PassthroughSubject<InteractivePostCatalogScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<InteractivePostCatalogScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    /// Held, so the SDK keeps each list current while the screen is up.
    private var threadLists: [(dmRoomID: String, list: RoomThreadListServiceProxyProtocol)] = []
    /// The template a catalogue link named: its page opens over the catalogue (decision 111).
    private let initialTemplateID: String?
    private let fetchCatalog: (URL) async -> SpiralAppCatalog.Fetched
    private let fetchArtifact: (SpiralAppTemplate, URL) async -> SpiralAppArtifact?
    private let fetchStill: (SpiralAppTemplate, URL) async -> UIImage?
    private let introductionSeen: () -> Void
    private var liveCard: InteractivePostCatalogLiveCard?

    /// Nil until the room's people are counted, or if they couldn't be read.
    private var peopleInRoom: Int?
    /// Which of the catalogue's screens are showing. Moving between them is an
    /// appearance and a disappearance in either order, so a disappearance is
    /// read a turn later; none shows once a thread or a dismissal covers them.
    private var screensShowing = Set<InteractivePostCatalogScreenID>()
    /// The preview has a pool of its own, which the timeline's background
    /// handling never reaches: in the background a killed process would
    /// restart the post, so nothing runs there.
    private var isInBackground = false

    init(roomName: String,
         catalogURL: URL,
         dms: [JoinedRoomProxyProtocol],
         ownUserID: String = "",
         initialTemplateID: String? = nil,
         assistant: InteractivePostCatalogAssistant = .available,
         hasSeenIntroduction: Bool = true,
         introductionSeen: @escaping () -> Void = { },
         livePreview: DraftPreview = DraftPreview(),
         fetchCatalog: @escaping (URL) async -> SpiralAppCatalog.Fetched = SpiralAppCatalog.fetch,
         fetchArtifact: @escaping (SpiralAppTemplate, URL) async -> SpiralAppArtifact? = SpiralAppCatalog.artifact,
         fetchStill: @escaping (SpiralAppTemplate, URL) async -> UIImage? = { await InteractivePostCatalogScreenViewModel.still(of: $0, from: $1) },
         countPeople: @escaping @MainActor () async -> Int? = { nil },
         loadMembers: @escaping @MainActor () async -> [String: Any] = { ["members": []] }) {
        self.initialTemplateID = initialTemplateID
        self.fetchCatalog = fetchCatalog
        self.fetchArtifact = fetchArtifact
        self.fetchStill = fetchStill
        self.introductionSeen = introductionSeen
        var state = InteractivePostCatalogScreenViewState(roomName: roomName,
                                                          catalogURL: catalogURL,
                                                          ownUserID: ownUserID,
                                                          assistant: assistant,
                                                          livePreview: livePreview)
        // A link names a post: it opens on that post, never on the introduction.
        state.hasSeenIntroduction = hasSeenIntroduction || initialTemplateID != nil
        super.init(initialViewState: state)

        let liveCard = InteractivePostCatalogLiveCard(preview: livePreview, viewerID: ownUserID, loadMembers: loadMembers)
        self.liveCard = liveCard
        liveCard.$runningTemplateID
            .sink { [weak self] in self?.state.runningTemplateID = $0 }
            .store(in: &cancellables)
        liveCard.$stills
            .sink { [weak self] in self?.state.stills = $0 }
            .store(in: &cancellables)
        observeApp()

        threadLists = dms.map { ($0.id, $0.threadListService()) }
        for (dmRoomID, list) in threadLists {
            list.itemsPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.rebuild() }
                .store(in: &cancellables)
            MXLog.info("[SpiralApp] catalogue reading the threads of \(dmRoomID)")
        }

        Task { await load() }
        Task {
            // No people at all is a read that failed: there is always the viewer.
            peopleInRoom = await countPeople().flatMap { $0 > 0 ? $0 : nil }
        }
        Task { await loadCatalog(from: catalogURL) }
    }

    /// A screen in a given state, for previews: nothing is fetched and nothing runs.
    init(previewState: InteractivePostCatalogScreenViewState) {
        initialTemplateID = nil
        fetchCatalog = { _ in .unavailable }
        fetchArtifact = { _, _ in nil }
        fetchStill = { _, _ in nil }
        introductionSeen = { }
        super.init(initialViewState: previewState)
    }

    /// The sheet is gone, however it went: nothing may keep the web view after it.
    func stop() {
        screensShowing.removeAll()
        liveCard?.run(nil)
    }

    override func process(viewAction: InteractivePostCatalogScreenViewAction) {
        switch viewAction {
        case .finishIntroduction:
            state.hasSeenIntroduction = true
            introductionSeen()
        case .selectSection(let sectionID):
            state.bindings.sectionID = sectionID
        case .openPost(let templateID):
            openPost(templateID)
        case .showPage(let templateID):
            guard var page = state.page, page.section.items.contains(templateID), page.currentID != templateID else { return }
            page.currentID = templateID
            state.page = page
            loadArtifactIfMissing(templateID)
            updateLiveCard()
        case .showYours:
            actionsSubject.send(.showYours)
        case .startNew(let description):
            actionsSubject.send(.startNew(description: description))
        case .openThread(let item):
            actionsSubject.send(.openThread(item))
        case .publishTemplate(let template):
            actionsSubject.send(.publishTemplate(template))
        case .changeTemplate(let template):
            actionsSubject.send(.changeTemplate(template))
        case .showAgents:
            actionsSubject.send(.showAgents)
        case .retryAgents(let templateID):
            actionsSubject.send(.retryAgents(templateID: templateID))
        case .retryCatalog:
            state.catalogLoad = .loading
            Task { await loadCatalog(from: state.catalogURL) }
        case .retryThreads:
            state.threadsLoad = .loading
            Task { await load() }
        case .screenAppeared(let screen):
            screensShowing.insert(screen)
            updateLiveCard()
        case .screenDisappeared(let screen):
            Task {
                screensShowing.remove(screen)
                updateLiveCard()
            }
        case .cancel:
            actionsSubject.send(.cancel)
        }
    }

    // MARK: - Private

    private func observeApp() {
        let center = NotificationCenter.default
        // While the app is still active, as a picture needs it to be.
        center.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.liveCard?.freezeRunningCard() }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.isInBackground = true
                self?.updateLiveCard()
            }
            .store(in: &cancellables)
        center.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.isInBackground = false
                self?.updateLiveCard()
            }
            .store(in: &cancellables)
    }

    /// The page swipes through the section the post was found in.
    private func openPost(_ templateID: String) {
        guard let section = state.homeSection(of: templateID) else {
            MXLog.info("[SpiralApp] catalogue: \(templateID) is in no section")
            return
        }
        state.page = InteractivePostCatalogPage(section: section, currentID: templateID)
        loadArtifactIfMissing(templateID)
        actionsSubject.send(.showPost)
    }

    /// The page's post gets the one running post, and only while the page is
    /// on top: never on the catalogue, under a thread, in the background, or
    /// before the post's files are here.
    private func updateLiveCard() {
        let mayRun = screensShowing.contains(.post) && !isInBackground
        guard mayRun, let templateID = state.page?.currentID, let artifact = state.artifacts[templateID] else {
            // Files on their way: the post already running, if any, carries on.
            if !mayRun {
                liveCard?.run(nil)
            }
            return
        }
        liveCard?.run(.init(templateID: templateID, artifact: artifact))
    }

    /// A template whose files didn't arrive gets another try from the person who wants it.
    private func loadArtifactIfMissing(_ templateID: String) {
        guard state.artifacts[templateID] == nil, let template = state.catalog?.template(templateID) else { return }
        Task { await loadArtifact(of: template, from: state.catalogURL) }
    }

    /// The catalogue, then every template's files and still: the page runs the
    /// template itself, so the files are read once, up front, and kept
    /// (§ 5.61); everywhere else a template shows its still (question 376).
    private func loadCatalog(from base: URL) async {
        let catalog: SpiralAppCatalog
        switch await fetchCatalog(base) {
        case .catalog(let fetched):
            catalog = fetched
        case .newerFormat:
            state.catalogLoad = .needsNewerApp
            return
        case .unavailable:
            state.catalogLoad = .failed
            return
        }

        state.catalog = catalog
        state.shelves = InteractivePostCatalogScreenViewState.shelves(of: catalog, peopleInRoom: peopleInRoom)
        state.catalogLoad = .loaded
        // A link's template opens on its page. An id that is on no shelf — not
        // in the catalogue, or in no section — opens the catalogue as any other time.
        if let initialTemplateID {
            if state.homeSection(of: initialTemplateID) != nil {
                openPost(initialTemplateID)
            } else {
                MXLog.info("[SpiralApp] catalogue link to \(initialTemplateID), which is no card")
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for template in catalog.items {
                group.addTask { await self.loadArtifact(of: template, from: base) }
                group.addTask { await self.loadStill(of: template, from: base) }
            }
        }
    }

    private func loadArtifact(of template: SpiralAppTemplate, from base: URL) async {
        guard let artifact = await fetchArtifact(template, base) else { return }
        state.artifacts[template.id] = artifact
        if template.id == state.page?.currentID {
            updateLiveCard()
        }
    }

    private func loadStill(of template: SpiralAppTemplate, from base: URL) async {
        guard let image = await fetchStill(template, base) else { return }
        state.catalogueStills[template.id] = image
    }

    /// A template's still from the catalogue, in the app's language
    /// (`SpiralAppTemplate.still(for:)`), or nil when it has none, it didn't
    /// arrive, or it is not the still the catalogue describes: the card then
    /// keeps its quiet grey until it runs.
    nonisolated static func still(of template: SpiralAppTemplate, from base: URL,
                                  languages: [String] = SpiralAppCatalog.appLanguages) async -> UIImage? {
        guard let still = template.still(for: languages), let data = await SpiralAppCatalog.data(at: still.path, from: base) else {
            return nil
        }
        if let expected = still.sha256, SpiralAppArtifact.digest(of: data) != expected {
            MXLog.error("[SpiralApp] catalogue \(still.path) is not the still its index describes")
            return nil
        }
        return UIImage(data: data)
    }

    private func load() async {
        // Two pages: a thread list page is a few dozen threads, and a
        // catalogue is for the recent ones.
        var failed = false
        for (_, list) in threadLists {
            for _ in 0..<2 {
                if case .idle(endReached: true) = list.paginationStatePublisher.value { break }
                if case .failure = await list.paginate() {
                    failed = true
                    break
                }
            }
        }
        rebuild()
        // Some of yours are still yours; none after a failed read is not "none".
        state.threadsLoad = failed && state.threads.isEmpty ? .failed : .loaded
    }

    private func rebuild() {
        state.threads = threadLists
            .flatMap { dmRoomID, list in
                list.itemsPublisher.value.compactMap { Self.item(from: $0, dmRoomID: dmRoomID) }
            }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// A thread whose root is a request this client wrote, else nil.
    ///
    /// The root's `com.spiral.interactive` is not in what the thread list
    /// gives back, so the root is recognised by its text — which is ours, and
    /// ends in the room's name between «».
    static func item(from thread: RoomThreadListItem, dmRoomID: String) -> InteractivePostThreadItem? {
        guard let root = thread.rootMessageDetails.message.map({ String($0.characters) }),
              let roomName = madeForRoomName(inRootText: root) else {
            return nil
        }
        let latest = thread.latestMessageDetails
        return InteractivePostThreadItem(id: thread.id,
                                         dmRoomID: dmRoomID,
                                         madeForRoomName: roomName,
                                         lastActivity: latest?.timestamp ?? thread.rootMessageDetails.timestamp,
                                         title: latest?.interactiveDraftTitle,
                                         lastMessage: latest?.message.map { String($0.characters) },
                                         replies: thread.numberOfReplies)
    }

    /// «Interactive post for «Група»» → «Група», in ANY language the app
    /// ships (§ 5.59).
    ///
    /// The root's text is written in the language the app had when the thread
    /// began, and the app's language can change since: matched only against
    /// the current one, every thread started in English vanished from «Yours»
    /// the day its strings were translated. So every shipped template is tried.
    static func madeForRoomName(inRootText text: String) -> String? {
        for (prefix, suffix) in requestBodyTemplates {
            guard let start = text.range(of: prefix) else { continue }
            let rest = text[start.upperBound...]
            if suffix.isEmpty {
                return String(rest).isEmpty ? nil : String(rest)
            }
            guard let end = rest.range(of: suffix, options: .backwards) else { continue }
            let name = String(rest[..<end.lowerBound])
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// The request root's text in every language that carries it, split
    /// around the room name — longest prefix first, so a longer template is
    /// not shadowed by one that is its start.
    static let requestBodyTemplates: [(prefix: String, suffix: String)] = {
        let key = "screen_room_interactive_post_request_body"
        var seen = Set<String>()
        var templates: [(prefix: String, suffix: String)] = []
        for language in Bundle.app.localizations {
            guard let bundle = Bundle.lprojBundle(for: language) else { continue }
            let format = bundle.localizedString(forKey: key, value: "\u{0}", table: "Untranslated")
            guard format != "\u{0}", format != key, seen.insert(format).inserted,
                  let hole = format.range(of: "%1$@") else { continue }
            let prefix = String(format[..<hole.lowerBound])
            guard !prefix.isEmpty else { continue }
            templates.append((prefix, String(format[hole.upperBound...])))
        }
        return templates.sorted { $0.prefix.count > $1.prefix.count }
    }()
}
