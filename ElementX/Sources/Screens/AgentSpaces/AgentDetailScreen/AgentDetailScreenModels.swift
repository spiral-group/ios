//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
import SpiralComponents

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
    /// The agent no longer exists (deleted elsewhere): the flow closes.
    case gone
}

struct AgentDetailScreenViewState: BindableState {
    /// The card the user tapped — renders the header instantly
    /// (including presence, which the read-model doesn't carry).
    let selection: AgentSelection
    /// The card as the spaces last read it (platform sync, decision 289): the header follows the list.
    var liveCard: AgentSpaceAgentCard?
    /// The sync's state at the top while the stream is not live.
    var syncStatus: PlatformSyncStatus?

    var detailState: AgentDetailScreenDetailState = .loading
    var isArchiving = false
    var isAddingToChat = false
    var bindings = AgentDetailScreenViewStateBindings()
    /// Pending cross-signing verification requests — drives the contextual
    /// banner (rendered only while there are some).
    var pendingVerifications: [VerificationSummary] = []
    /// The owner's DM with this agent, so its row reads as that.
    var ownerDMRoomID: String?
    /// The agent's chats' names on this device, by room id; a chat this device isn't in has none.
    var deviceRoomNames: [String: String] = [:]
    /// This agent's approvals waiting for the owner; `nil` until they are
    /// read, never a made-up `0`.
    var pendingApprovalsCount: Int?
    /// The first read of what waits is on its way: its slot shows a placeholder.
    var isReadingPendingApprovals = true
    /// The people this agent blocks, from the first page; `nil` until read
    /// or when the read failed, never a made-up `0`.
    var blockedCount: AgentBlockedCount?
    /// The first read of the blocks is on its way: its slot shows a placeholder.
    var isReadingBlocked = true
    var isPausing = false
    /// The switch's new position while the write is on its way.
    var pendingPause: Bool?
    var isWritingVisibility = false
    /// «Показывать в поиске»'s new position while the write is on its way.
    var pendingShowInSearch: Bool?

    var card: AgentSpaceAgentCard {
        liveCard ?? selection.card
    }

    /// The title a room row shows.
    func title(for room: AgentRoomEntry) -> String {
        room.title(ownerDMRoomID: ownerDMRoomID, agentName: displayName, deviceName: deviceRoomNames[room.roomID])
    }

    /// Decision 153: the personal assistant is not archived.
    var canArchive: Bool {
        !card.isPersonalAssistant
    }

    /// The outreach queue: the backend refuses enqueue for every other role. A company role, so off with them (396).
    var showsQueue: Bool {
        SpiralFeatures.companySpaces && card.kind == "outreach"
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
    
    /// The profile card's status: the card's, with the pause this screen read.
    var presence: SpiralAgentStatus? {
        card.presence(isPaused: isPaused)
    }
    
    /// The pause switch: the card's until the agent is read.
    var paused: Bool {
        pendingPause ?? isPaused
    }
    
    /// A switch shows the card's value at once, and writes only over what was read.
    var canWriteSwitches: Bool {
        readModel != nil
    }
    
    /// A role agent's «Общение с людьми» would hold only «Показывать в
    /// поиске», so the switch sits in «Настройки» itself; the assistant's
    /// screen has the visitor choices and greeting too.
    var showsPeopleSettings: Bool {
        card.isPersonalAssistant
    }
    
    /// The search switch on this screen: the card's until the agent is read.
    var showInSearch: Bool? {
        guard !showsPeopleSettings else { return nil }
        return pendingShowInSearch ?? ((readModel?.visibility ?? card.visibility) == "public")
    }
    
    /// «Звонки» holds only the call language, which the card doesn't carry. Assistants are provisioned with one, so
    /// the row keeps its place until a read says this one has none; only then does the row go.
    var showsCallsSettings: Bool {
        guard card.isPersonalAssistant else { return false }
        guard let readModel else { return true }
        return readModel.voiceLanguage != nil
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

enum AgentDetailScreenViewAction: CustomStringConvertible {
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
    /// Read again after a failure.
    case retry
    
    /// A room's name, a person's in a DM, ships in bug reports: the log names the room by its ID.
    var description: String {
        switch self {
        case .selectRoom(let entry): "selectRoom(\(entry.roomID))"
        case .edit: "edit"
        case .message: "message"
        case .addToChat: "addToChat"
        case .openVerification: "openVerification"
        case .openActivity: "openActivity"
        case .openUsage: "openUsage"
        case .openQueue: "openQueue"
        case .openSettings(let section): "openSettings(\(section))"
        case .openPendingApprovals: "openPendingApprovals"
        case .openBlocked: "openBlocked"
        case .setPaused(let isPaused): "setPaused(\(isPaused))"
        case .setShowInSearch(let isShown): "setShowInSearch(\(isShown))"
        case .archiveTapped: "archiveTapped"
        case .confirmArchive: "confirmArchive"
        case .retry: "retry"
        }
    }
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
