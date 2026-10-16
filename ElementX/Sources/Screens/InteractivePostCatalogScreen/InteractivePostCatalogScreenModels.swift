//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066, § 5.56): what «+ → Interactive post» opens.
// A new post described in words, or one of yours from before — each is a
// generation thread in your DM with the agent, and the thread is the record.
//

import Foundation

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
    case startNew
    case openThread(InteractivePostThreadItem)
    case publishTemplate(SpiralAppTemplate)
    case changeTemplate(SpiralAppTemplate)
    /// «Yours › All»: the full list, pushed (§ 5.63).
    case showAllThreads
    case cancel
}

struct InteractivePostCatalogScreenViewState: BindableState {
    /// Where a post from here goes: the room «+» was pressed in.
    let roomName: String
    /// Where the catalogue's files are (`index.json`, thumbnails).
    let catalogURL: URL
    /// Who is looking: the preview runs as them, as the post will.
    let ownUserID: String
    /// The people of the room «+» was pressed in, as `members.basic.read`
    /// answers them — a template is previewed with the room it would go to.
    let loadMembers: @MainActor () async -> [String: Any]
    /// Whether the viewer has an agent to make posts with. A catalogue link
    /// opens for anyone (decision 129): without one, only browse and Publish.
    var assistant = InteractivePostCatalogAssistant.available
    var catalog: SpiralAppCatalog?
    /// Every template packed as the room would receive it, by id — read once
    /// the catalogue arrives, so each row runs the template itself (§ 5.61).
    var artifacts: [String: SpiralAppArtifact] = [:]
    var threads: [InteractivePostThreadItem] = []
    var isLoading = true
    /// Bumped by every chip tap: the carousel is rebuilt from its first card
    /// (§ 5.80). Setting `currentCardID` alone did not scroll it — the offset
    /// of the old, longer row stayed, clamped to the new one's end.
    var carouselGeneration = 0
    
    var bindings = InteractivePostCatalogScreenViewStateBindings()
}

struct InteractivePostCatalogScreenViewStateBindings {
    /// The section the carousel is filtered to; nil is all of them (§ 5.63).
    var section: String?
    /// The card the carousel rests on — its title, actions and dot follow.
    var currentCardID: InteractivePostCatalogCard.ID?
}

/// One card of the carousel: a template, or «Describe a new one» at the end.
enum InteractivePostCatalogCard: Identifiable, Equatable {
    case template(SpiralAppTemplate)
    case describeNew

    var id: String {
        switch self {
        case .template(let template): template.id
        case .describeNew: "describe-new"
        }
    }

    var template: SpiralAppTemplate? {
        if case .template(let template) = self { template } else { nil }
    }
}

extension InteractivePostCatalogScreenViewState {
    /// The carousel: the templates of the chosen section (or all, in the
    /// catalogue's order), then «Describe a new one» for someone with an agent.
    var cards: [InteractivePostCatalogCard] {
        let describeNew: [InteractivePostCatalogCard] = assistant == .available ? [.describeNew] : []
        guard let catalog else { return describeNew }
        let sections = catalog.sections.filter { bindings.section == nil || $0.id == bindings.section }
        let templates = sections.flatMap { $0.items.compactMap(catalog.template) }
        return templates.map { .template($0) } + describeNew
    }

    /// The card the carousel rests on; the first when nothing has moved.
    var currentCard: InteractivePostCatalogCard? {
        cards.first { $0.id == bindings.currentCardID } ?? cards.first
    }

    /// How many cards away from the one the carousel rests on — what decides
    /// whether a card runs (`InteractivePostCatalogTemplateCell.liveReach`).
    func distance(of card: InteractivePostCatalogCard) -> Int {
        let cards = cards
        guard let index = cards.firstIndex(of: card),
              let current = currentCard.flatMap({ cards.firstIndex(of: $0) }) else {
            return .max
        }
        return abs(index - current)
    }

    /// The section a template is in, for the line under the card.
    func sectionTitle(of template: SpiralAppTemplate) -> String? {
        catalog?.sections.first { $0.items.contains(template.id) }?.localizedTitle
    }

    /// The newest few threads for the main screen; the rest behind «All».
    /// Ones with a draft to name them first: a thread whose last word is a
    /// «📌 Published» note is the same post, already sent.
    var recentThreads: [InteractivePostThreadItem] {
        let named = threads.filter { $0.title != nil }
        return Array((named + threads.filter { $0.title == nil }).prefix(3))
    }
}

enum InteractivePostCatalogScreenViewAction {
    case startNew
    case openThread(InteractivePostThreadItem)
    case publishTemplate(SpiralAppTemplate)
    case changeTemplate(SpiralAppTemplate)
    case showAllThreads
    case selectSection(String?)
    case cancel
}
