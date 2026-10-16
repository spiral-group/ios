//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (§ 5.56): your earlier posts are your generation threads.
// No store of their own: the DM's thread list (MSC3856) is read, the threads
// whose root is an Interactive Post request kept, newest first.
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
    /// The template a catalogue link named: the carousel opens on it (decision 111).
    private let initialTemplateID: String?

    init(roomName: String,
         catalogURL: URL,
         dms: [JoinedRoomProxyProtocol],
         ownUserID: String = "",
         initialTemplateID: String? = nil,
         assistant: InteractivePostCatalogAssistant = .available,
         loadMembers: @escaping @MainActor () async -> [String: Any] = { ["members": []] }) {
        self.initialTemplateID = initialTemplateID
        super.init(initialViewState: InteractivePostCatalogScreenViewState(roomName: roomName,
                                                                           catalogURL: catalogURL,
                                                                           ownUserID: ownUserID,
                                                                           loadMembers: loadMembers,
                                                                           assistant: assistant))

        threadLists = dms.map { ($0.id, $0.threadListService()) }
        for (dmRoomID, list) in threadLists {
            list.itemsPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.rebuild() }
                .store(in: &cancellables)
            MXLog.info("[SpiralApp] catalogue reading the threads of \(dmRoomID)")
        }

        Task { await load() }
        Task { await loadCatalog(from: catalogURL) }
    }

    override func process(viewAction: InteractivePostCatalogScreenViewAction) {
        switch viewAction {
        case .startNew:
            actionsSubject.send(.startNew)
        case .openThread(let item):
            actionsSubject.send(.openThread(item))
        case .publishTemplate(let template):
            actionsSubject.send(.publishTemplate(template))
        case .changeTemplate(let template):
            actionsSubject.send(.changeTemplate(template))
        case .showAllThreads:
            actionsSubject.send(.showAllThreads)
        case .selectSection(let section):
            // A new page of cards: rest on its first, whatever the last was —
            // also when the chip tapped is the one already on (§ 5.80).
            state.bindings.section = section
            state.bindings.currentCardID = state.cards.first?.id
            state.carouselGeneration += 1
        case .cancel:
            actionsSubject.send(.cancel)
        }
    }

    // MARK: - Private

    /// The catalogue, then every template's files: the rows run the templates
    /// themselves, so the files are read once, up front, and kept (§ 5.61).
    private func loadCatalog(from base: URL) async {
        guard let catalog = await SpiralAppCatalog.load(from: base) else { return }
        state.catalog = catalog
        // A link's template, in all sections, rebuilt so the carousel opens
        // there. An id that is no card — not in the catalogue, or in no
        // section — leaves it on the first card.
        if let initialTemplateID {
            state.bindings.section = nil
            if state.cards.contains(where: { $0.template?.id == initialTemplateID }) {
                state.bindings.currentCardID = initialTemplateID
                state.carouselGeneration += 1
            } else {
                MXLog.info("[SpiralApp] catalogue link to \(initialTemplateID), which is no card")
            }
        }
        await withTaskGroup(of: (String, SpiralAppArtifact?).self) { group in
            for template in catalog.items {
                group.addTask { await (template.id, SpiralAppCatalog.artifact(of: template, from: base)) }
            }
            for await (id, artifact) in group {
                if let artifact {
                    state.artifacts[id] = artifact
                }
            }
        }
    }

    private func load() async {
        // Two pages: a thread list page is a few dozen threads, and a
        // catalogue is for the recent ones.
        for (_, list) in threadLists {
            for _ in 0..<2 {
                if case .idle(endReached: true) = list.paginationStatePublisher.value { break }
                _ = await list.paginate()
            }
        }
        rebuild()
        state.isLoading = false
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
