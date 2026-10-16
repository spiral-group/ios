//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: client-rendered notices (Brief 0073).
//

import Compound
import SwiftUI

/// The card for a `com.spiral.notice`. Shaped like the ended-call tile
/// (`CallNotificationRoomTimelineView`): icon, two lines, the time; the
/// tile is the action — for a referral, it opens the newcomer's profile.
struct SpiralNoticeRoomTimelineView: View {
    @Environment(\.openURL) private var openURL
    // Nil outside a timeline (previews): a relayed note then names its sender by MXID.
    @Environment(\.timelineContext) private var context
    
    let timelineItem: SpiralNoticeRoomTimelineItem
    
    /// A relayed note's sender by name, once their profile is read. Keyed by
    /// the user it is for: a recycled row keeps its state for the next notice.
    @State private var relayedSender: (userID: String, displayName: String)?

    /// Whether the reader allowed AI, for the AI consent notice: nil until read.
    @State private var readerAllowsAI: Bool?
    
    var body: some View {
        HStack(spacing: 12) {
            CompoundIcon(icon, size: .medium, relativeTo: .compound.headingMDBold)
                .foregroundStyle(.compound.iconAccentPrimary)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.compound.bodyMDSemibold)
                    .foregroundColor(.compound.textPrimary)
                Text(subtitle)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
                    .lineLimit(isOneLine ? 1 : nil)
                    .truncationMode(.middle)
                if let actionTitle {
                    Text(actionTitle)
                        .font(.compound.bodySMSemibold)
                        .foregroundColor(.compound.textActionAccent)
                        .padding(.top, 6)
                }
            }
            
            Spacer(minLength: 8)
            
            Text(timelineItem.timestamp.formattedTime())
                .font(.compound.bodyXS)
                .foregroundColor(.compound.textSecondary)
        }
        .padding(12)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(.compound.borderInteractiveSecondary, lineWidth: 1))
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActionable ? .isButton : .isStaticText)
        .accessibilityHint(hint ?? "")
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.spiralNotice(timelineItem.notice.kind.wireName))
        .task(id: relayedFromUserID) { await resolveRelayedSender() }
        .task(id: timelineItem.id) { await resolveReaderAllowsAI() }
    }
    
    private var icon: KeyPath<CompoundIcons, Image> {
        switch timelineItem.notice.kind {
        case .referralJoined: \.userAdd
        case .welcome: \.chat
        case .phraseChanged: \.key
        case .replyFailed: \.error
        case .replyWithheld: \.info
        case .aiBudgetReached: \.time
        case .messagePassedToOwner: \.send
        case .introSuggestion: \.userProfile
        case .summaryMovedToDM: \.info
        case .recordingMovedToDM: \.voiceCall
        case .relayedToOwner: \.forward
        case .aiConsentNeeded: \.lock
        }
    }
    
    private var title: String {
        switch timelineItem.notice.kind {
        case .referralJoined: UntranslatedL10n.noticeReferralJoinedTitle
        case .welcome(let ownerDisplayName, _, _): UntranslatedL10n.noticeWelcomeTitle(ownerDisplayName)
        case .phraseChanged: UntranslatedL10n.noticePhraseChangedTitle
        case .replyFailed: UntranslatedL10n.noticeReplyFailedTitle
        case .replyWithheld: UntranslatedL10n.noticeReplyWithheldTitle
        case .aiBudgetReached: UntranslatedL10n.noticeAiBudgetReachedTitle
        case .messagePassedToOwner: UntranslatedL10n.noticeMessagePassedTitle
        case .introSuggestion: UntranslatedL10n.noticeIntroSuggestionTitle
        case .summaryMovedToDM: UntranslatedL10n.noticeSummaryMovedTitle
        case .recordingMovedToDM: UntranslatedL10n.noticeRecordingMovedTitle
        case .relayedToOwner(_, let fromUserID, _):
            Self.relayedTitle(fromUserID: fromUserID,
                              ownUserID: context?.viewState.ownUserID,
                              displayName: relayedSenderName(fromUserID))
        case .aiConsentNeeded: UntranslatedL10n.noticeAiConsentNeededTitle
        }
    }
    
    private var subtitle: String {
        switch timelineItem.notice.kind {
        // The name first; the MXID is the fallback and the link's target.
        case .referralJoined(let joinedUserID, let joinedDisplayName): joinedDisplayName ?? joinedUserID
        // The assistant's name as the room knows it now, so a rename reads
        // through the welcome too; the name the server sent is the fallback
        // while the profile is still loading.
        case .welcome(_, let agentDisplayName, let behavior):
            behavior == "personal_assistant"
                ? UntranslatedL10n.noticeWelcomeAssistantBody(Self.liveName(sender: timelineItem.sender, fallback: agentDisplayName))
                : UntranslatedL10n.noticeWelcomeAgentBody(Self.liveName(sender: timelineItem.sender, fallback: agentDisplayName))
        case .phraseChanged(let deviceName):
            if let deviceName {
                "\(UntranslatedL10n.noticePhraseChangedOnDevice(deviceName)) \(UntranslatedL10n.noticePhraseChangedBody)"
            } else {
                UntranslatedL10n.noticePhraseChangedBody
            }
        case .replyFailed:
            UntranslatedL10n.noticeReplyFailedBody
        case .replyWithheld:
            UntranslatedL10n.noticeReplyWithheldBody
        // The reset is the next UTC midnight: within a day, so the time says it.
        case .aiBudgetReached(let resetsAt):
            UntranslatedL10n.noticeAiBudgetReachedBody(resetsAt.formatted(date: .omitted, time: .shortened))
        // The owner's own greeting, when they wrote one, then the promise.
        case .messagePassedToOwner(let ownerDisplayName, let greeting):
            [greeting, UntranslatedL10n.noticeMessagePassedBody(ownerDisplayName)]
                .compactMap(\.self)
                .joined(separator: "\n\n")
        case .introSuggestion(_, let summary, let suggestedOpener):
            "\(summary)\n\n\(UntranslatedL10n.noticeIntroSuggestionOpener(suggestedOpener))"
        case .summaryMovedToDM:
            UntranslatedL10n.noticeSummaryMovedBody
        case .recordingMovedToDM:
            UntranslatedL10n.noticeRecordingMovedBody
        // The note, then where it was said: the room by name, never its ID.
        case .relayedToOwner(let note, _, let roomID):
            "\(note)\n\n\(Self.relayedRoomLine(roomName: context?.viewState.roomNameForIDResolver?(roomID)))"
        case .aiConsentNeeded(let agentDisplayName):
            Self.aiConsentBody(agentName: Self.liveName(sender: timelineItem.sender, fallback: agentDisplayName),
                               readerAllowsAI: readerAllowsAI)
        }
    }

    /// Decision 150. Someone who has allowed AI since — or anyone else reading
    /// the room who has — is not asked to; a failed read still offers the way.
    static func aiConsentBody(agentName: String, readerAllowsAI: Bool?) -> String {
        readerAllowsAI == true
            ? UntranslatedL10n.noticeAiConsentNeededAllowedBody(agentName)
            : UntranslatedL10n.noticeAiConsentNeededBody(agentName)
    }

    /// The visible action under a card's text; nil for the cards whose tile alone opens something.
    private var actionTitle: String? {
        guard case .aiConsentNeeded = timelineItem.notice.kind, readerAllowsAI != true else { return nil }
        return UntranslatedL10n.noticeAiConsentNeededAction
    }
    
    /// The cards that open a person when tapped.
    private var isActionable: Bool {
        switch timelineItem.notice.kind {
        case .referralJoined, .introSuggestion: true
        case .relayedToOwner(_, let fromUserID, _): fromUserID != context?.viewState.ownUserID
        case .aiConsentNeeded: readerAllowsAI != true
        case .welcome, .phraseChanged, .replyFailed, .replyWithheld, .aiBudgetReached, .messagePassedToOwner,
             .summaryMovedToDM, .recordingMovedToDM: false
        }
    }
    
    /// A referral's subtitle is a name; every other card is read and may
    /// run several lines.
    private var isOneLine: Bool {
        if case .referralJoined = timelineItem.notice.kind { return true }
        return false
    }
    
    private var hint: String? {
        guard isActionable else { return nil }
        if case .aiConsentNeeded = timelineItem.notice.kind { return nil } // The action's own words say it.
        return UntranslatedL10n.noticeReferralJoinedHint
    }
    
    /// "From you", "From Bob" — or the MXID until their name is known.
    static func relayedTitle(fromUserID: String, ownUserID: String?, displayName: String?) -> String {
        if fromUserID == ownUserID {
            return UntranslatedL10n.noticeRelayedToOwnerTitleYou
        }
        return UntranslatedL10n.noticeRelayedToOwnerTitle(displayName ?? fromUserID)
    }
    
    /// A room the owner is in has a name here; the visitor's DM with the
    /// assistant, where most notes come from, has none.
    static func relayedRoomLine(roomName: String?) -> String {
        guard let roomName = roomName?.trimmingCharacters(in: .whitespacesAndNewlines), !roomName.isEmpty else {
            return UntranslatedL10n.noticeRelayedToOwnerRoomUnknown
        }
        return UntranslatedL10n.noticeRelayedToOwnerRoom(roomName)
    }
    
    /// Someone other than the owner whose note this is; nil for every other card.
    private var relayedFromUserID: String? {
        guard case .relayedToOwner(_, let fromUserID, _) = timelineItem.notice.kind,
              fromUserID != context?.viewState.ownUserID else {
            return nil
        }
        return fromUserID
    }
    
    /// A member of this room by their name here; anyone else once their profile is read.
    private func relayedSenderName(_ userID: String) -> String? {
        if let name = context?.viewState.members[userID]?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        guard let relayedSender, relayedSender.userID == userID else { return nil }
        return relayedSender.displayName
    }
    
    private func resolveReaderAllowsAI() async {
        guard case .aiConsentNeeded = timelineItem.notice.kind,
              let resolver = context?.viewState.spiralAIConsentResolver else { return }
        readerAllowsAI = await resolver()
    }

    private func resolveRelayedSender() async {
        guard let userID = relayedFromUserID, relayedSenderName(userID) == nil,
              let name = await context?.viewState.spiralDisplayNameResolver?(userID) else {
            return
        }
        relayedSender = (userID, name)
    }
    
    static func liveName(sender: TimelineItemSender, fallback: String) -> String {
        guard let name = sender.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return fallback
        }
        return name
    }
    
    /// The person's profile, through the same link a pill would open: the
    /// newcomer, or the agent an intro suggests. The AI consent notice opens
    /// the AI toggle.
    private func open() {
        let userID: String
        switch timelineItem.notice.kind {
        case .aiConsentNeeded:
            guard isActionable else { return }
            context?.send(viewAction: .openAIConsentSettings)
            return
        case .referralJoined(let joinedUserID, _): userID = joinedUserID
        case .introSuggestion(let candidateAgentID, _, _): userID = candidateAgentID
        case .relayedToOwner(_, let fromUserID, _):
            guard isActionable else { return }
            userID = fromUserID
        case .welcome, .phraseChanged, .replyFailed, .replyWithheld, .aiBudgetReached, .messagePassedToOwner,
             .summaryMovedToDM, .recordingMovedToDM:
            return
        }
        guard let url = SpiralLink(userID: userID)?.webURL else { return }
        openURL(url)
    }
}

// MARK: - Previews

struct SpiralNoticeRoomTimelineView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        SpiralNoticeRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                         timestamp: .mock,
                                                         sender: .init(id: "@assistant-emmm:spiral.md", displayName: "Emmm's Assistant"),
                                                         notice: SpiralNotice(msgtype: SpiralNotice.msgtype,
                                                                              data: #"{"com.spiral.notice":{"kind":"referral_joined","joined_user_id":"@diana:spiral.md"}}"#)!))
            .previewDisplayName("Referral joined")
        SpiralNoticeRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                         timestamp: .mock,
                                                         sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                                         notice: SpiralNotice(msgtype: SpiralNotice.msgtype,
                                                                              data: #"{"com.spiral.notice":{"kind":"welcome","owner_display_name":"Alice","agent_display_name":"Alice's Assistant","behavior":"personal_assistant"}}"#)!))
            .previewDisplayName("Welcome")
        SpiralNoticeRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                         timestamp: .mock,
                                                         sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                                         notice: SpiralNotice(msgtype: SpiralNotice.msgtype,
                                                                              data: #"{"com.spiral.notice":{"kind":"phrase_changed","device_name":"Spiral на iPhone 15"}}"#)!))
            .previewDisplayName("Phrase changed")
        SpiralNoticeRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                         timestamp: .mock,
                                                         sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                                         notice: SpiralNotice(msgtype: SpiralNotice.msgtype,
                                                                              data: #"{"com.spiral.notice":{"kind":"phrase_changed"}}"#)!))
            .previewDisplayName("Phrase changed, device unknown")
        notice(#"{"kind":"reply_failed"}"#)
            .previewDisplayName("Reply failed")
        notice(#"{"kind":"reply_withheld"}"#)
            .previewDisplayName("Reply withheld")
        notice(#"{"kind":"ai_budget_reached","resets_at":"2026-10-11T00:00:00Z"}"#)
            .previewDisplayName("AI budget reached")
        notice(#"{"kind":"message_passed_to_owner","owner_display_name":"Alice"}"#)
            .previewDisplayName("Message passed to the owner")
        notice(#"{"kind":"message_passed_to_owner","owner_display_name":"Alice","greeting":"Hi! Alice is travelling this week."}"#)
            .previewDisplayName("Message passed, the owner's greeting")
        notice(#"{"kind":"intro_suggestion","candidate_agent_mxid":"@assistant-carlos:spiral.md","summary":"Carlos builds iOS tools — close to what you asked about.","suggested_opener":"Hi Carlos, could we compare notes on TestFlight?"}"#)
            .previewDisplayName("Intro suggestion")
        notice(#"{"kind":"summary_moved_to_dm","room_id":"!call:spiral.md"}"#)
            .previewDisplayName("Summary moved to the DM")
        notice(#"{"kind":"recording_moved_to_dm","room_id":"!call:spiral.md"}"#)
            .previewDisplayName("Recording moved to the DM")
        // Decision 38. In a timeline: the sender is a member there, the room one the owner is in.
        notice(#"{"kind":"relayed_to_owner","note":"Bob is running 20 minutes late and asks you to start without him.","from_user_id":"@bob:matrix.org","room_id":"!room:matrix.org"}"#)
            .environment(\.timelineContext, TimelineViewModel.mock.context)
            .previewDisplayName("Relayed to the owner")
        notice(#"{"kind":"relayed_to_owner","note":"Bob is running 20 minutes late and asks you to start without him.","from_user_id":"@bob:spiral.md","room_id":"!visitor:spiral.md"}"#)
            .previewDisplayName("Relayed to the owner, names unknown")
        notice(#"{"kind":"ai_consent_needed","agent_display_name":"Alice's Assistant"}"#)
            .previewDisplayName("AI consent needed")
    }
    
    private static func notice(_ facts: String) -> SpiralNoticeRoomTimelineView {
        SpiralNoticeRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                         timestamp: .mock,
                                                         sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                                         notice: SpiralNotice(msgtype: SpiralNotice.msgtype,
                                                                              data: #"{"com.spiral.notice":"# + facts + "}")!))
    }
}
