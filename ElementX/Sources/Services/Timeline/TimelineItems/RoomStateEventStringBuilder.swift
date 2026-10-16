//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDK
import UIKit

nonisolated struct RoomStateEventStringBuilder {
    let userID: String
    
    func buildString(for change: MembershipChange?,
                     reason: String?,
                     memberUserID: String,
                     memberDisplayName: String?,
                     sender: TimelineItemSender,
                     isOutgoing: Bool) -> String? {
        guard let change else {
            MXLog.verbose("Filtering timeline item for membership change that is nil")
            return nil
        }
        
        let senderIsYou = isOutgoing
        let memberIsYou = memberUserID == userID
        let member = memberDisplayName ?? memberUserID
        let senderDisplayName = sender.disambiguatedDisplayName ?? sender.id
        
        switch change {
        case .joined:
            return memberIsYou ? L10n.stateEventRoomJoinByYou : L10n.stateEventRoomJoin(senderDisplayName)
        case .left:
            return memberIsYou ? L10n.stateEventRoomLeaveByYou : L10n.stateEventRoomLeave(member)
        case .banned, .kickedAndBanned:
            return switch (senderIsYou, reason) {
            case (true, .some(let reason)): L10n.stateEventRoomBanByYouWithReason(member, reason)
            case (true, .none): L10n.stateEventRoomBanByYou(member)
            case (false, .some(let reason)): L10n.stateEventRoomBanWithReason(senderDisplayName, member, reason)
            case (false, .none): L10n.stateEventRoomBan(senderDisplayName, member)
            }
        case .unbanned:
            return senderIsYou ? L10n.stateEventRoomUnbanByYou(member) : L10n.stateEventRoomUnban(senderDisplayName, member)
        case .kicked:
            return switch (senderIsYou, reason) {
            case (true, .some(let reason)): L10n.stateEventRoomRemoveByYouWithReason(member, reason)
            case (true, .none): L10n.stateEventRoomRemoveByYou(member)
            case (false, .some(let reason)): L10n.stateEventRoomRemoveWithReason(senderDisplayName, member, reason)
            case (false, .none): L10n.stateEventRoomRemove(senderDisplayName, member)
            }
        case .invited:
            if senderIsYou {
                return L10n.stateEventRoomInviteByYou(member)
            } else if memberIsYou {
                return buildInvitedYouString(senderDisplayName)
            } else {
                return L10n.stateEventRoomInvite(senderDisplayName, member)
            }
        case .invitationAccepted:
            return memberIsYou ? L10n.stateEventRoomInviteAcceptedByYou : L10n.stateEventRoomInviteAccepted(member)
        case .invitationRejected:
            return memberIsYou ? L10n.stateEventRoomRejectByYou : L10n.stateEventRoomReject(senderDisplayName)
        case .invitationRevoked:
            return senderIsYou ? L10n.stateEventRoomThirdPartyRevokedInviteByYou(member) : L10n.stateEventRoomThirdPartyRevokedInvite(senderDisplayName, member)
        case .knocked:
            return memberIsYou ? L10n.stateEventRoomKnockByYou : L10n.stateEventRoomKnock(member)
        case .knockAccepted:
            return senderIsYou ? L10n.stateEventRoomKnockAcceptedByYou(member) : L10n.stateEventRoomKnockAccepted(senderDisplayName, member)
        case .knockRetracted:
            return memberIsYou ? L10n.stateEventRoomKnockRetractedByYou : L10n.stateEventRoomKnockRetracted(member)
        case .knockDenied:
            if senderIsYou {
                return L10n.stateEventRoomKnockDeniedByYou(member)
            } else if memberIsYou {
                return L10n.stateEventRoomKnockDeniedYou(senderDisplayName)
            } else {
                return L10n.stateEventRoomKnockDenied(senderDisplayName, member)
            }
        case .none, .error, .notImplemented: // Not useful information for the user.
            MXLog.verbose("Filtering timeline item for membership change: \(change)")
            return nil
        }
    }
    
    func buildInvitedYouString(_ senderDisplayName: String) -> String {
        L10n.stateEventRoomInviteYou(senderDisplayName)
    }
    
    func buildProfileChangeString(displayName: String?, previousDisplayName: String?,
                                  avatarURLString: String?, previousAvatarURLString: String?,
                                  member: String, memberIsYou: Bool) -> String? {
        let displayNameChanged = displayName != previousDisplayName
        let avatarChanged = avatarURLString != previousAvatarURLString
        
        switch (displayNameChanged, avatarChanged, memberIsYou) {
        case (true, false, false):
            if let displayName, let previousDisplayName {
                return L10n.stateEventDisplayNameChangedFrom(member, previousDisplayName, displayName)
            } else if let displayName {
                return L10n.stateEventDisplayNameSet(member, displayName)
            } else if let previousDisplayName {
                return L10n.stateEventDisplayNameRemoved(member, previousDisplayName)
            } else {
                MXLog.error("The display name changed from nil to nil, filtering the item.")
                return nil
            }
        case (false, true, false):
            return L10n.stateEventAvatarUrlChanged(displayName ?? member)
        case (true, false, true):
            if let displayName, let previousDisplayName {
                return L10n.stateEventDisplayNameChangedFromByYou(previousDisplayName, displayName)
            } else if let displayName {
                return L10n.stateEventDisplayNameSetByYou(displayName)
            } else if let previousDisplayName {
                return L10n.stateEventDisplayNameRemovedByYou(previousDisplayName)
            } else {
                MXLog.error("The display name changed from nil to nil, filtering the item.")
                return nil
            }
        case (false, true, true):
            return L10n.stateEventAvatarUrlChangedByYou
        case (true, true, _):
            // When both have changed, get the string for the display name and tack on that the avatar changed too.
            guard let string = buildProfileChangeString(displayName: displayName, previousDisplayName: previousDisplayName,
                                                        avatarURLString: nil, previousAvatarURLString: nil,
                                                        member: member, memberIsYou: memberIsYou) else { return nil }
            return string + "\n" + L10n.stateEventAvatarChangedToo
        case (false, false, _):
            MXLog.error("Nothing changed, shouldn't be possible. Filtering the item.")
            return nil
        }
    }
    
    func buildString(for state: OtherState, sender: TimelineItemSender, isOutgoing: Bool, rawEventJSON: String? = nil) -> String? {
        let displayName = sender.disambiguatedDisplayName ?? sender.id
        
        switch state {
        case .roomAvatar(let url):
            switch (url, isOutgoing) {
            case (.some, false):
                return L10n.stateEventRoomAvatarChanged(displayName)
            case (nil, false):
                return L10n.stateEventRoomAvatarRemoved(displayName)
            case (.some, true):
                return L10n.stateEventRoomAvatarChangedByYou
            case (nil, true):
                return L10n.stateEventRoomAvatarRemovedByYou
            }
        case .roomCreate:
            return isOutgoing ? L10n.stateEventRoomCreatedByYou : L10n.stateEventRoomCreated(displayName)
        case .roomEncryption:
            return L10n.commonEncryptionEnabled
        case .roomName(let name):
            switch (name, isOutgoing) {
            case (.some(let name), false):
                return L10n.stateEventRoomNameChanged(displayName, name)
            case (nil, false):
                return L10n.stateEventRoomNameRemoved(displayName)
            case (.some(let name), true):
                return L10n.stateEventRoomNameChangedByYou(name)
            case (nil, true):
                return L10n.stateEventRoomNameRemovedByYou
            }
        case .roomThirdPartyInvite(let displayName):
            guard let displayName else {
                MXLog.error("roomThirdPartyInvite undisplayable due to missing name.")
                return nil
            }
            
            if isOutgoing {
                return L10n.stateEventRoomThirdPartyInviteByYou(displayName)
            } else {
                return L10n.stateEventRoomThirdPartyInvite(displayName, displayName)
            }
        case .roomTopic(let topic):
            switch (topic, isOutgoing) {
            case (.some(let topic), false) where !topic.isBlank:
                return L10n.stateEventRoomTopicChanged(displayName, topic)
            case (_, false):
                return L10n.stateEventRoomTopicRemoved(displayName)
            case (.some(let topic), true) where !topic.isBlank:
                return L10n.stateEventRoomTopicChangedByYou(topic)
            case (_, true):
                return L10n.stateEventRoomTopicRemovedByYou
            }
        case .roomPinnedEvents(let change):
            switch change {
            case .added:
                return isOutgoing ? L10n.stateEventRoomPinnedEventsPinnedByYou : L10n.stateEventRoomPinnedEventsPinned(displayName)
            case .changed:
                return isOutgoing ? L10n.stateEventRoomPinnedEventsChangedByYou : L10n.stateEventRoomPinnedEventsChanged(displayName)
            case .removed:
                return isOutgoing ? L10n.stateEventRoomPinnedEventsUnpinnedByYou : L10n.stateEventRoomPinnedEventsUnpinned(displayName)
            }
        case .roomPowerLevels: // Long term we might show only the user changes, but we need an SDK filter to fix read receipts in that case.
            break
        case .policyRuleRoom, .policyRuleServer, .policyRuleUser: // No strings available.
            break
        case .roomCanonicalAlias: // Doesn't provide the alias.
            break
        case .roomGuestAccess, .roomHistoryVisibility: // Doesn't provide information about the change.
            break
        case .roomJoinRules: // Doesn't provide information about the change.
            break
        case .roomServerAcl: // Doesn't provide information about the change.
            break
        case .roomTombstone: // Handle as a virtual timeline item with a link to the upgraded room.
            break
        case .spaceChild, .spaceParent: // Users shouldn't see the timeline of a Space.
            break
        case .custom(let eventType):
            // AGENT-PLATFORM (Brief 0043/0044, ADR-0057/0058): Spiral room
            // facts render as quiet gray rows for EVERY participant. The
            // factory now hands us the event's raw JSON, so we render the
            // CURRENT tool state ("Agent: translating to English") instead
            // of a generic "updated tools" line; we fall back to the
            // generic line when the JSON isn't available or doesn't parse.
            if eventType == "com.spiral.tools" {
                if let rawEventJSON,
                   let event = SpiralToolsStateReader.parseEvent(rawEventJSON: rawEventJSON) {
                    return spiralToolsLine(agentName: displayName, tools: event.tools)
                }
                return UntranslatedL10n.stateEventSpiralToolsUpdated(displayName)
            }
            // Other custom types: no actionable information.
        }
        
        MXLog.verbose("Filtering timeline item for state: \(state)")
        return nil
    }

    // MARK: - AGENT-PLATFORM (Brief 0044, ADR-0058)

    /// AGENT-PLATFORM (Brief 0066 § 5.89): the line for the agent-tools
    /// FALLBACK — the message-like event the platform sends when the room
    /// refused the agent's `com.spiral.tools` state row. It says the same
    /// thing, so it reads the same; nil unless it is a fallback from one of
    /// this server's agents.
    func buildSpiralToolsFallbackString(rawEventJSON: String, sender: TimelineItemSender) -> String? {
        guard let event = SpiralToolsStateReader.parseFallbackEvent(rawEventJSON: rawEventJSON, ownUserID: userID) else {
            return nil
        }
        return spiralToolsLine(agentName: sender.disambiguatedDisplayName ?? sender.id, tools: event.tools)
    }

    /// Compact gray-row line for a `com.spiral.tools` state event: the
    /// agent's CURRENT tools. Empty tools = "turned all tools off"; otherwise
    /// EVERY active tool is listed by name, joined with " · " — the event is a
    /// full snapshot of the agent's tools, so the row shows the complete
    /// current set rather than hiding the rest behind a "+N". Names reuse the
    /// arm-tool / banner titles so the surfaces never drift.
    private func spiralToolsLine(agentName: String, tools: [ToolsBannerEntry.Tool]) -> String {
        guard !tools.isEmpty else {
            return UntranslatedL10n.stateEventSpiralToolsOff(agentName)
        }
        let line = tools.map(spiralToolText(for:)).joined(separator: " · ")
        return UntranslatedL10n.stateEventSpiralToolsActive(agentName, line)
    }

    /// One tool's compact name — translate shows its target language, every
    /// other kind (including the call-artifact tools) its localized name via
    /// `ToolDisplayName`, so a call summary / recording tool never falls back
    /// to a raw "Call_summary" tag.
    private func spiralToolText(for tool: ToolsBannerEntry.Tool) -> String {
        if tool.kind == "translate" || tool.kind == "live_translate",
           let language = tool.targetLanguage {
            return UntranslatedL10n.screenAgentToolsListTitleTranslate(TranslationLanguageDisplayName.localizedName(for: language))
        }
        return ToolDisplayName.name(forKind: tool.kind)
    }
}
