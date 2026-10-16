//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

// AGENT-PLATFORM: Brief 0037, reworked by the Agents tab step B (decision
// 191): the room details layout — avatar, name with presence, handle, a kind
// line, four buttons «Написать» · «В чат» · «Активность» · «Использование»,
// the agent's chats, a role agent's brief and its Archive at the bottom.

enum AgentDetailScreenViewModelAction {
    case selectRoom(AgentRoomEntry)
    case showEdit
    case showVerification(id: String)
    case showActivity
    case showUsage
    case showQueue
    /// «Написать»: the owner's DM with the agent.
    case message
    /// «В чат»: pick a chat for the agent, which is already in these.
    case addToChat(agentRoomIDs: Set<String>)
    /// The agent joined a chat the owner picked.
    case addedToChat
    /// One of «Настройки».
    case showSettings(AgentSettingsSection)
    /// «Ждут вашего решения»: this agent's actions waiting for the owner.
    case showPendingApprovals
    /// «Заблокированные».
    case showBlocked
    /// A choice on this screen (the pause) landed.
    case changed
    /// Archived — the flow closes and the list reloads.
    case archived
}

struct AgentDetailScreenViewState: BindableState {
    /// The card the user tapped — renders the header instantly
    /// (including presence, which the read-model doesn't carry).
    let selection: AgentSelection

    var detailState: AgentDetailScreenDetailState = .loading
    var isArchiving = false
    var isAddingToChat = false
    var bindings = AgentDetailScreenViewStateBindings()
    /// Pending cross-signing verification requests — drives the contextual
    /// banner (rendered only while there are some).
    var pendingVerifications: [VerificationSummary] = []
    /// The owner's DM with this agent, so its row reads as that.
    var ownerDMRoomID: String?
    /// This agent's approvals waiting for the owner; `nil` while the stream
    /// isn't connected to say, never a made-up `0`.
    var pendingApprovalsCount: Int?
    /// The people this agent blocks, from the first page; `nil` until read
    /// or when the read failed, never a made-up `0`.
    var blockedCount: AgentBlockedCount?
    var isPausing = false
    /// The switch's new position while the write is on its way.
    var pendingPause: Bool?
    var isWritingVisibility = false
    /// «Показывать в поиске»'s new position while the write is on its way.
    var pendingShowInSearch: Bool?

    var card: AgentSpaceAgentCard {
        selection.card
    }

    /// The title a room row shows.
    func title(for room: AgentRoomEntry) -> String {
        room.title(ownerDMRoomID: ownerDMRoomID, agentName: displayName)
    }

    /// Decision 153: the personal assistant is not archived.
    var canArchive: Bool {
        !card.isPersonalAssistant
    }

    /// The outreach queue: the backend refuses enqueue for every other role.
    var showsQueue: Bool {
        card.kind == "outreach"
    }

    /// «ваш личный ассистент» / «Продажи · Кофейня Зерно».
    var kindLine: String? {
        if card.isPersonalAssistant {
            return UntranslatedL10n.screenAgentDetailKindPersonalAssistant
        }
        let parts = [card.localizedRole, selection.companyName].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var displayName: String {
        readModel?.displayName ?? card.displayName
    }

    var avatarMXC: String? {
        readModel?.avatarMXC ?? card.avatarMXC
    }

    /// «На паузе» under the name (decision 194).
    var isPaused: Bool {
        readModel?.paused ?? card.isPaused
    }
    
    /// The pause switch, once the agent is read.
    var paused: Bool? {
        guard let readModel else { return nil }
        return pendingPause ?? readModel.paused
    }
    
    /// A role agent's «Общение с людьми» would hold only «Показывать в
    /// поиске», so the switch sits in «Настройки» itself; the assistant's
    /// screen has the visitor choices and greeting too.
    var showsPeopleSettings: Bool {
        card.isPersonalAssistant
    }
    
    /// The search switch on this screen, once the agent is read.
    var showInSearch: Bool? {
        guard !showsPeopleSettings, let readModel else { return nil }
        return pendingShowInSearch ?? (readModel.visibility == "public")
    }
    
    /// «Звонки» holds only the call language, so it shows with it.
    var showsCallsSettings: Bool {
        card.isPersonalAssistant && readModel?.voiceLanguage != nil
    }
    
    var characterTitle: String {
        card.isPersonalAssistant ? UntranslatedL10n.screenAgentEditPersonaSection : UntranslatedL10n.screenCreateAgentRoleBriefSection
    }

    var readModel: AgentReadModel? {
        if case .loaded(let readModel, _) = detailState { return readModel }
        return nil
    }
    
    /// The chats the agent is in, as last read.
    var agentRoomIDs: Set<String> {
        guard case .loaded(_, let rooms) = detailState else { return [] }
        return Set(rooms.map(\.roomID))
    }
}

extension RoomSummary {
    /// Whether «В чат» offers this chat: one the owner is in that the agent
    /// would join usefully. Not a space, not a chat the agent is in (its own
    /// list, or a member the summary shows), and not a DM with one other
    /// person — that conversation is theirs. A group the owner is in is fine.
    func canTakeAgent(matrixUserID: String, agentRoomIDs: Set<String>) -> Bool {
        guard joinRequestType == nil, !isSpace, !isTombstoned else { return false }
        guard !agentRoomIDs.contains(id), !heroes.contains(where: { $0.id == matrixUserID }) else { return false }
        return !(isDirect && activeMembersCount <= 2)
    }
}

enum AgentDetailScreenDetailState: Equatable {
    case loading
    case loaded(AgentReadModel, [AgentRoomEntry])
    case failure
}

struct AgentDetailScreenViewStateBindings {
    var alertInfo: AlertInfo<AgentDetailScreenAlertType>?
}

enum AgentDetailScreenAlertType: Hashable {
    case confirmArchive
    case archiveFailed
    /// The server refused (409): the agent stays with the account.
    case archiveRefused
    case addToChatFailed
    /// «В чат» on a chat the agent is already in.
    case alreadyInChat
}

enum AgentDetailScreenViewAction {
    case selectRoom(AgentRoomEntry)
    case edit
    case message
    case addToChat
    case openVerification
    case openActivity
    case openUsage
    case openQueue
    case openSettings(AgentSettingsSection)
    case openPendingApprovals
    case openBlocked
    case setPaused(Bool)
    case setShowInSearch(Bool)
    /// Archive — asks for confirmation first.
    case archiveTapped
    case confirmArchive
    /// Full retry after a failure — flips back to `.loading` first.
    case retry
    /// Silent pull-to-refresh — keeps the current content on screen.
    case refresh
}

extension AgentRoomEntry {
    /// What the agent does in the chat: its tools by name, or «Без инструментов».
    var toolsLine: String {
        guard !activeTools.isEmpty else {
            return UntranslatedL10n.screenAgentDetailNoTools
        }
        return activeTools.map(\.localizedTitle).joined(separator: ", ")
    }
}
