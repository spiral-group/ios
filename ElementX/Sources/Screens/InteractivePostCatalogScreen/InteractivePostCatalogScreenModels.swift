//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, § 5.56, question 412 concept G): what «+ → Interactive post»
// opens. A light catalogue of stills with search and sections, a post page where a post
// is tried before it is sent, and yours: a new post described in words or one from before,
// each a generation thread in your DM with the agent, and the thread is the record.
//

import SFSafeSymbols
import SwiftUI

/// What the catalogue knows of the viewer's agents (decision 129): the
/// assistant's paths show only for `.available`, and the other three say
/// different things under a template that has to be filled in.
nonisolated enum InteractivePostCatalogAssistant: Equatable {
    case available
    /// None, and none on the way: create one.
    case none
    /// None yet: a fresh account's agent is still being provisioned.
    case settingUp
    /// The agents couldn't be read — never reported as "none".
    case unknown
}

/// One of your earlier interactive posts: a generation thread in the DM.
struct InteractivePostThreadItem: Identifiable, Equatable {
    /// The thread's root event id.
    let id: String
    let dmRoomID: String
    /// The room it was made for, as the root says it.
    let madeForRoomName: String
    let lastActivity: Date
    /// The newest draft's title, when the thread's last word is a draft.
    let title: String?
    /// What the thread said last, otherwise.
    let lastMessage: String?
    let replies: UInt
}

enum InteractivePostCatalogScreenViewModelAction {
    /// A thread with the agent, opening with these words when there are any.
    case startNew(description: String?)
    case openThread(InteractivePostThreadItem)
    case publishTemplate(SpiralAppTemplate)
    case changeTemplate(SpiralAppTemplate)
    /// The Agents tab, where the person's agent is or will be (question 412).
    case showAgents
    /// The agents couldn't be read: read them again, back on this post.
    case retryAgents(templateID: String)
    /// The post page, pushed over the catalogue.
    case showPost
    /// Yours, pushed over the catalogue.
    case showYours
    case cancel
}

/// The screens the one running post can show on. Named rather than counted: SwiftUI may
/// report an appearance twice, and a count that drifts keeps a web view running for ever.
enum InteractivePostCatalogScreenID: Hashable {
    case catalogue
    case post
    case yours
}

/// How reading a list went. A failure is never an empty list.
enum InteractivePostCatalogLoad: Equatable {
    case loading
    case loaded
    case failed
    /// `index.json` is in a format newer than this build (decision 96).
    case needsNewerApp
}

/// What the post page offers under a post (question 412, concept A1).
enum InteractivePostCatalogChoiceAction: Equatable {
    /// A plain template: Send. Changing it first needs an agent.
    case publish(canChange: Bool)
    /// A template that is only a shape until the agent fills it.
    case fillIn(ask: String)
    /// The same, for someone with no agent: the way to one.
    case createAgent
    /// The same, while the agent is still being set up: the way to one, waiting.
    case agentSettingUp
    /// The same, when the agents couldn't be read: never "create one" (decision 129).
    case agentUnknown
}

/// One line on a post's page: who it is for, or how it plays (question 412).
struct InteractivePostCatalogFact: Equatable, Identifiable {
    let id: String
    let symbol: SFSymbol
    let text: String

    /// The most a post page shows: who it is for, then how it plays.
    static let maximum = 3

    /// A template's facts as the page shows them: players first, then its traits
    /// in the catalogue's order. Nothing for a catalogue packed before them.
    static func facts(of template: SpiralAppTemplate) -> [InteractivePostCatalogFact] {
        var facts = template.players.map { [players($0)] } ?? []
        facts += template.traits.map { trait($0, players: template.players) }
        return Array(facts.prefix(maximum))
    }

    private static func players(_ players: SpiralAppTemplate.Players) -> InteractivePostCatalogFact {
        switch players {
        case .solo: .init(id: "players", symbol: .person, text: UntranslatedL10n.screenInteractiveCatalogFactPlayersSolo)
        case .two: .init(id: "players", symbol: .person2, text: UntranslatedL10n.screenInteractiveCatalogFactPlayersTwo)
        case .group: .init(id: "players", symbol: .person3, text: UntranslatedL10n.screenInteractiveCatalogFactPlayersGroup)
        }
    }

    private static func trait(_ trait: SpiralAppTemplate.Trait, players: SpiralAppTemplate.Players?) -> InteractivePostCatalogFact {
        let (symbol, text): (SFSymbol, String) = switch trait {
        case .sealed: (.eyeSlash, players == .two ? UntranslatedL10n.screenInteractiveCatalogFactSealedTwo : UntranslatedL10n.screenInteractiveCatalogFactSealed)
        case .secret: (.lock, UntranslatedL10n.screenInteractiveCatalogFactSecret)
        case .turns: (.arrowLeftArrowRight, UntranslatedL10n.screenInteractiveCatalogFactTurns)
        case .live: (.dotRadiowavesLeftAndRight, UntranslatedL10n.screenInteractiveCatalogFactLive)
        case .sameForAll: (.equalCircle, UntranslatedL10n.screenInteractiveCatalogFactSameForAll)
        case .score: (.trophy, UntranslatedL10n.screenInteractiveCatalogFactScore)
        case .names: (.personTextRectangle, UntranslatedL10n.screenInteractiveCatalogFactNames)
        case .agentFills: (.sparkles, UntranslatedL10n.screenInteractiveCatalogFactAgentFills)
        case .shown: (.eye, UntranslatedL10n.screenInteractiveCatalogFactShown)
        case .together: (.plusCircle, UntranslatedL10n.screenInteractiveCatalogFactTogether)
        }
        return .init(id: trait.rawValue, symbol: symbol, text: text)
    }
}

/// What the catalogue shows under its chips.
enum InteractivePostCatalogContent: Equatable {
    /// Every section, a shelf each.
    case shelves([SpiralAppCatalog.Section])
    /// One section, or what a search found, as a grid.
    case grid([SpiralAppTemplate])
    /// A search that found nothing.
    case noResults(query: String)
}

/// The post page: the posts it swipes through, one section's, and the one on screen.
struct InteractivePostCatalogPage: Equatable {
    let section: SpiralAppCatalog.Section
    var currentID: String

    var position: Int {
        (section.items.firstIndex(of: currentID) ?? 0) + 1
    }
}

struct InteractivePostCatalogScreenViewState: BindableState {
    /// Where a post from here goes: the room «+» was pressed in.
    let roomName: String
    /// Where the catalogue's files are (`index.json`, stills).
    let catalogURL: URL
    /// Who is looking: the preview runs as them, as the post will.
    let ownUserID: String
    /// Whether the viewer has an agent to make posts with. A catalogue link
    /// opens for anyone (decision 129): without one, only browse and Send.
    var assistant = InteractivePostCatalogAssistant.available
    /// The screen's one running post, on the post page.
    let livePreview: DraftPreview

    /// The one-time introduction is over, or was never wanted (a link).
    var hasSeenIntroduction = true
    var catalog: SpiralAppCatalog?
    var catalogLoad = InteractivePostCatalogLoad.loading
    /// The catalogue's sections as this room shows them, ordered once, as the
    /// catalogue arrives: shelves never move under a reader.
    var shelves: [SpiralAppCatalog.Section] = []
    /// Every template packed as the room would receive it, by id — read once
    /// the catalogue arrives, so the page runs the template itself (§ 5.61).
    var artifacts: [String: SpiralAppArtifact] = [:]
    var threads: [InteractivePostThreadItem] = []
    var threadsLoad = InteractivePostCatalogLoad.loading

    /// The post page, while it is pushed or on its way.
    var page: InteractivePostCatalogPage?
    /// The template holding the running post right now.
    var runningTemplateID: String?
    /// What each post that has run last looked like.
    var stills: [String: UIImage] = [:]
    /// Each template at rest: the catalogue's own still (question 376), in
    /// the app's language — uk, ru, or English for everyone else (question 412).
    var catalogueStills: [String: UIImage] = [:]

    var bindings = InteractivePostCatalogScreenViewStateBindings()
}

struct InteractivePostCatalogScreenViewStateBindings {
    var searchQuery = ""
    /// The section chip chosen, nil for «All».
    var sectionID: String?
}

extension InteractivePostCatalogScreenViewState {
    /// Only someone with an agent has anything of their own to open.
    var hasYours: Bool {
        assistant == .available
    }

    var trimmedQuery: String {
        bindings.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The chips' sections, then the search, decide what shows.
    var content: InteractivePostCatalogContent {
        let query = trimmedQuery
        let chosen = bindings.sectionID.flatMap(section)
        guard !query.isEmpty else {
            return chosen.map { .grid(templates(of: $0)) } ?? .shelves(shelves)
        }
        let sections = chosen.map { [$0] } ?? shelves
        var seen = Set<String>()
        let found = sections
            .flatMap { section in templates(of: section).filter { matches($0, in: section, query: query) } }
            .filter { seen.insert($0.id).inserted }
        return found.isEmpty ? .noResults(query: query) : .grid(found)
    }

    /// A template's own words, and the name of any section it is in.
    func matches(_ template: SpiralAppTemplate, in section: SpiralAppCatalog.Section, query: String) -> Bool {
        [template.localizedTitle, template.localizedDescription, section.localizedTitle].contains { $0.localizedStandardContains(query) }
    }

    func templates(of section: SpiralAppCatalog.Section) -> [SpiralAppTemplate] {
        section.items.compactMap { catalog?.template($0) }
    }

    func section(_ id: String) -> SpiralAppCatalog.Section? {
        shelves.first { $0.id == id }
    }

    /// The first section on screen that holds a template: the one its page swipes through.
    func homeSection(of templateID: String) -> SpiralAppCatalog.Section? {
        if let chosen = bindings.sectionID.flatMap(section), chosen.items.contains(templateID) {
            return chosen
        }
        return shelves.first { $0.items.contains(templateID) }
    }

    /// The still a post shows when it isn't the running one: as it was left, or the catalogue's.
    func still(of templateID: String) -> UIImage? {
        stills[templateID] ?? catalogueStills[templateID]
    }

    /// The introduction's fan, left, middle, right (question 412, introduction C): three real posts
    /// with little text — dots and boxes, the who's-it wheel, sea battle — chosen when stills were
    /// English for everyone (question 384). Stills are now drawn in uk, ru and en (question 412), so
    /// these read in the app's language too. A catalogue without one of them takes the next template it holds.
    var introductionTemplateIDs: [String] {
        let wanted = ["dots", "who-wheel", "sea-battle"]
        let held = shelves.flatMap(\.items)
        var spare = held.filter { !wanted.contains($0) }.makeIterator()
        return wanted.compactMap { held.contains($0) ? $0 : spare.next() }
    }

    /// The catalogue's «New» slider: every new template in the catalogue's order, over the
    /// shelves only — a chosen section or a search shows what was asked for.
    var newCardTemplates: [SpiralAppTemplate] {
        guard trimmedQuery.isEmpty, bindings.sectionID == nil, let catalog else { return [] }
        // Only ones a shelf holds: a page swipes through its shelf's section. The catalogue drops duplicates.
        return catalog.newIDs.filter { id in shelves.contains { $0.items.contains(id) } }.compactMap(catalog.template)
    }

    /// Whether a card wears the small «New» badge.
    func isNew(_ templateID: String) -> Bool {
        catalog?.newIDs.contains(templateID) ?? false
    }

    /// The first thing a room is likely to want: a game for two in a room of
    /// two, otherwise a way to decide. Unknown people leave the catalogue's
    /// own order.
    static func shelves(of catalog: SpiralAppCatalog, peopleInRoom: Int?) -> [SpiralAppCatalog.Section] {
        guard let peopleInRoom else { return catalog.sections }
        let first = peopleInRoom == 2 ? "two" : "decide"
        return catalog.sections.filter { $0.id == first } + catalog.sections.filter { $0.id != first }
    }

    func choiceAction(for template: SpiralAppTemplate) -> InteractivePostCatalogChoiceAction {
        guard let ask = template.localizedAsk else {
            return .publish(canChange: assistant == .available)
        }
        switch assistant {
        case .available: return .fillIn(ask: ask)
        case .none: return .createAgent
        case .settingUp: return .agentSettingUp
        case .unknown: return .agentUnknown
        }
    }

    /// Send's whole sentence for VoiceOver: the button itself only says «Send» (question 412, A1).
    var sendAccessibilityLabel: String {
        UntranslatedL10n.a11yInteractivePostSendToChat(roomName)
    }
}

enum InteractivePostCatalogScreenViewAction {
    case finishIntroduction
    case selectSection(String?)
    case openPost(templateID: String)
    /// The page swiped to another post of its section.
    case showPage(templateID: String)
    case showYours
    case startNew(description: String?)
    case openThread(InteractivePostThreadItem)
    case publishTemplate(SpiralAppTemplate)
    case changeTemplate(SpiralAppTemplate)
    case showAgents
    case retryAgents(templateID: String)
    case retryCatalog
    case retryThreads
    case screenAppeared(InteractivePostCatalogScreenID)
    case screenDisappeared(InteractivePostCatalogScreenID)
    case cancel
}
