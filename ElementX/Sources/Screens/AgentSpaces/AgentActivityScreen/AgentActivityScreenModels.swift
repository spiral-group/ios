//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenModels.swift`.

import Foundation

// MARK: - View ↔ ViewModel state

/// Top-level state of the activity timeline.
///
/// Diverges from `VerificationsListState` / `ApprovalsListState`
/// in one structural way: `.loaded` carries both the accumulated
/// items AND the load-more state for the bottom sentinel. The
/// sibling list screens model "all items already in hand" — this
/// screen accumulates pages via the cursor.
enum AgentActivityListState: Equatable {
    /// First-page fetch in flight (or filter just changed and we
    /// cleared accumulated items).
    case loading
    /// Page resolved. `items` accumulates across pages until
    /// either the filter changes (full clear) or pull-to-refresh
    /// fires (also a full clear). `loadMore` drives the sentinel
    /// row at the bottom; see `LoadMoreState` for the four
    /// possible affordances.
    case loaded([AgentActivityListItem], loadMore: LoadMoreState)
    /// First-page fetch failed before any items arrived. Inline
    /// retry CTA.
    case failed
}

/// Sentinel state for the row at the bottom of the timeline.
/// Mirrors the four shapes a "load more" widget can take in iOS
/// list patterns; pulling them into an enum keeps the View
/// branchable on one value rather than two booleans + a string.
enum LoadMoreState: Equatable {
    /// Terminal — no more rows to fetch. Sentinel hidden.
    case exhausted
    /// More rows available; tapping the sentinel (or scrolling
    /// to it via `.onAppear`) triggers the next page fetch.
    case idle(cursor: String)
    /// Fetch in flight. Sentinel renders a `ProgressView`.
    case loading
    /// Previous load-more attempt failed. Sentinel renders
    /// "Failed to load more — tap to retry" with the cursor
    /// preserved so the user doesn't lose place.
    case failed(cursor: String)
}

/// Display DTO for one row. Mapped from `AgentActivityEntry`
/// (the service-layer type) so the view never imports
/// `AgentPlatformClient`. The owner-facing words are computed here at
/// mapping time (`AgentActivityLabels`) so the View body stays a thin Form.
struct AgentActivityListItem: Identifiable, Equatable {
    let id: String
    /// Stable capability identifier (e.g. `messenger.reply_in_room`); picks
    /// the row icon and is never shown.
    let capabilityName: String
    /// Wire policy decision tag. Used to pick row icon + chip.
    let policyDecision: AgentActionPolicyDecision
    /// Wire outcome tag. Drives chip colour + label.
    let outcome: AgentActionOutcome
    /// What the agent did, as the owner reads it.
    let title: String
    /// Why it was allowed, asked or dropped — `nil` for a reason code this
    /// build doesn't know.
    let reason: String?
    /// The room the action was in, as the owner reads it (`AgentRoomLabel`);
    /// nil for an action outside a room.
    let roomName: String?
    /// Wall-clock instant the row was appended.
    let createdAt: Date
    /// Where a tap goes (G5): the approval it waits on, else its chat.
    var roomID: String?
    var approvalID: String?
    /// The agent that acted, for a feed of several agents (the hub).
    var agentID: String?
    var agentName: String?
}

/// The owner-facing words for an activity row (re-walk R3). Capability ids,
/// policy reason codes and the strategy's free-text reasoning are internal
/// («pre-llm wake-gate skip (Brief 0011…)», «armed tool 01a1… fired») and
/// are never shown. A code this build doesn't know reads as "Other action"
/// (an action) or adds nothing (a reason), so a newer backend degrades
/// instead of leaking its ids (decision 96).
nonisolated enum AgentActivityLabels {
    static func action(forCapability name: String) -> String {
        switch name {
        case "messenger.reply_in_room": UntranslatedL10n.screenAgentActivityActionRepliedInChat
        case "messenger.reply_in_owner_dm": UntranslatedL10n.screenAgentActivityActionRepliedToYou
        case "messenger.dm_owner": UntranslatedL10n.screenAgentActivityActionMessagedYou
        case "messenger.compose_structured_reply": UntranslatedL10n.screenAgentActivityActionFormattedReply
        case "messenger.summarize_room": UntranslatedL10n.screenAgentActivityActionSummarisedChat
        case "messenger.list_room_members": UntranslatedL10n.screenAgentActivityActionListedMembers
        case "messenger.notice_in_room": UntranslatedL10n.screenAgentActivityActionPostedNotice
        // These two notices go where the dropped message came from (a
        // visitor's room, decision 150), not to the owner.
        case "messenger.notice_reply_failed": UntranslatedL10n.screenAgentActivityActionSaidReplyNotSent
        case "messenger.notice_ai_consent_needed": UntranslatedL10n.screenAgentActivityActionToldAiNotAllowed
        // The visitor choice «Не отвечать» (decision 194): the one notice the person gets.
        case "messenger.notice_message_passed_to_owner": UntranslatedL10n.screenAgentActivityActionSaidMessagePassedOn
        case "messenger.notice_ai_budget_reached": UntranslatedL10n.screenAgentActivityActionAiLimitReached
        case "messenger.block_sender", "contact.owner_block": UntranslatedL10n.screenAgentActivityActionBlockedSomeone
        case "contact.unblock", "contact.owner_unblock": UntranslatedL10n.screenAgentActivityActionUnblockedSomeone
        case "social.search_agents": UntranslatedL10n.screenAgentActivityActionSearchedAgents
        case "social.read_agent_profile": UntranslatedL10n.screenAgentActivityActionReadAgentProfile
        case "social.propose_intro": UntranslatedL10n.screenAgentActivityActionSuggestedIntro
        case "memory.remember_about_contact": UntranslatedL10n.screenAgentActivityActionRemembered
        case "memory.recall_about_contact": UntranslatedL10n.screenAgentActivityActionRecalled
        case "schedule.create_action": UntranslatedL10n.screenAgentActivityActionSetReminder
        case "schedule.list_actions": UntranslatedL10n.screenAgentActivityActionListedReminders
        case "schedule.cancel_action": UntranslatedL10n.screenAgentActivityActionCancelledReminder
        case "voice.answer_call": UntranslatedL10n.screenAgentActivityActionAnsweredCall
        case "voice.leave_call": UntranslatedL10n.screenAgentActivityActionLeftCall
        case "voice.switch_mode": UntranslatedL10n.screenAgentActivityActionChangedCallMode
        case "voice.summarize_so_far": UntranslatedL10n.screenAgentActivityActionSummarisedCallSoFar
        case "voice.list_recent_calls": UntranslatedL10n.screenAgentActivityActionListedCalls
        case "voice.fetch_call_summary": UntranslatedL10n.screenAgentActivityActionReadCallSummary
        case "voice.fetch_call_transcript_window": UntranslatedL10n.screenAgentActivityActionReadCallTranscript
        case "session.set_control": UntranslatedL10n.screenAgentActivityActionChangedCallSetting
        case "session.save_as_room_default": UntranslatedL10n.screenAgentActivityActionSavedCallSettings
        case "tool.arm": UntranslatedL10n.screenAgentActivityActionTurnedOnTool
        case "tool.disable": UntranslatedL10n.screenAgentActivityActionTurnedOffTool
        case "tool.fire": UntranslatedL10n.screenAgentActivityActionUsedTool
        case "interactive.draft": UntranslatedL10n.screenAgentActivityActionDraftedPost
        case "interactive.studio": UntranslatedL10n.screenAgentActivityActionWorkedOnPost
        case "interactive.post": UntranslatedL10n.screenAgentActivityActionPublishedPost
        default: UntranslatedL10n.screenAgentActivityActionOther
        }
    }

    /// Codes from the backend's `AllowReason` / `ConsentReason` /
    /// `DenialReason` / `IgnoreReason` (`decision.rs`) and the few rows
    /// written outside the policy engine.
    static func reason(forPolicyReason code: String, capabilityName: String) -> String? {
        // The runtime acts as the owner for these on its own (a call it
        // answers, a reminder or notice it sends, an armed tool): nobody asked.
        if code == "owner_bypass", isAutomatic(capabilityName) {
            return nil
        }
        return reason(forPolicyReason: code)
    }
    
    /// Whether the agent runs this without anyone asking at that moment.
    /// Every notice is the runtime's own (`messenger.notice_*`: tools turned
    /// on, a reply that failed, a message passed on), so a new one is too.
    static func isAutomatic(_ capabilityName: String) -> Bool {
        capabilityName.hasPrefix("messenger.notice_") || automaticCapabilities.contains(capabilityName)
    }
    
    private static let automaticCapabilities: Set<String> = ["voice.answer_call", "voice.leave_call", "voice.switch_mode",
                                                             "messenger.dm_owner", "tool.fire"]
    
    static func reason(forPolicyReason code: String) -> String? {
        switch code {
        case "owner_bypass": UntranslatedL10n.screenAgentActivityReasonOwnerBypass
        case "relationship_approved": UntranslatedL10n.screenAgentActivityReasonRelationshipApproved
        case "capability_always_allowed": UntranslatedL10n.screenAgentActivityReasonCapabilityAlwaysAllowed
        case "agent_in_target_room": UntranslatedL10n.screenAgentActivityReasonAgentInTargetRoom
        case "group_room_trust_implicit": UntranslatedL10n.screenAgentActivityReasonGroupRoomTrustImplicit
        case "tool_armed_by_owner": UntranslatedL10n.screenAgentActivityReasonToolArmedByOwner
        case "ai_consent_needed_notice": UntranslatedL10n.screenAgentActivityReasonAiConsentNeededNotice
        case "ai_budget_notice": UntranslatedL10n.screenAgentActivityReasonAiBudgetNotice
        // The visitor choices (decision 194): «Отвечать сразу», and the notice of «Не отвечать».
        case "visitor_policy_reply": UntranslatedL10n.screenAgentActivityReasonVisitorPolicyReply
        case "message_passed_to_owner_notice": UntranslatedL10n.screenAgentActivityReasonMessagePassedToOwnerNotice
        case "first_contact_with_unknown_visitor": UntranslatedL10n.screenAgentActivityReasonFirstContactWithUnknownVisitor
        case "escalation_rule_match": UntranslatedL10n.screenAgentActivityReasonEscalationRuleMatch
        case "capability_always_requires_consent": UntranslatedL10n.screenAgentActivityReasonCapabilityAlwaysRequiresConsent
        case "block_needs_owner": UntranslatedL10n.screenAgentActivityReasonBlockNeedsOwner
        case "unknown_capability": UntranslatedL10n.screenAgentActivityReasonUnknownCapability
        case "input_validation_failed": UntranslatedL10n.screenAgentActivityReasonInputValidationFailed
        case "agent_not_in_room": UntranslatedL10n.screenAgentActivityReasonAgentNotInRoom
        case "owner_not_configured": UntranslatedL10n.screenAgentActivityReasonOwnerNotConfigured
        case "contact_not_approved": UntranslatedL10n.screenAgentActivityReasonContactNotApproved
        case "wrong_room_kind": UntranslatedL10n.screenAgentActivityReasonWrongRoomKind
        case "sender_is_owner": UntranslatedL10n.screenAgentActivityReasonSenderIsOwner
        case "no_contact_relationship": UntranslatedL10n.screenAgentActivityReasonNoContactRelationship
        case "outside_conversation": UntranslatedL10n.screenAgentActivityReasonOutsideConversation
        // The model asked for something its run did not offer (security pass 2): refused by the gate.
        case "not_offered": UntranslatedL10n.screenAgentActivityReasonNotOffered
        case "blocked_visitor": UntranslatedL10n.screenAgentActivityReasonBlockedVisitor
        case "strategy_no_op": UntranslatedL10n.screenAgentActivityReasonStrategyNoOp
        case "group_room_not_woken": UntranslatedL10n.screenAgentActivityReasonGroupRoomNotWoken
        case "notice_would_need_consent": UntranslatedL10n.screenAgentActivityReasonNoticeWouldNeedConsent
        case "rate_limited": UntranslatedL10n.screenAgentActivityReasonRateLimited
        case "already_asked_owner": UntranslatedL10n.screenAgentActivityReasonAlreadyAskedOwner
        case "booth_displacement_voice_master": UntranslatedL10n.screenAgentActivityReasonBoothDisplacementVoiceMaster
        case "relationship_unavailable": UntranslatedL10n.screenAgentActivityReasonRelationshipUnavailable
        default: nil
        }
    }

    /// The trailing outcome word — the filter vocabulary, one wording source.
    static func outcome(_ outcome: AgentActionOutcome) -> String {
        switch outcome {
        case .executed: UntranslatedL10n.screenAgentActivityFilterExecuted
        case .pending: UntranslatedL10n.screenAgentActivityFilterPendingConsent
        case .denied: UntranslatedL10n.screenAgentActivityFilterDenied
        case .declined: UntranslatedL10n.screenAgentActivityFilterDeclined
        case .cancelled: UntranslatedL10n.screenAgentActivityFilterCancelled
        case .failed: UntranslatedL10n.screenAgentActivityFilterFailed
        case .ignored: UntranslatedL10n.screenAgentActivityFilterIgnored
        case .unknown: UntranslatedL10n.screenAgentActivityOutcomeOther
        }
    }
}

struct AgentActivityScreenViewState: BindableState {
    var listState: AgentActivityListState = .loading
    /// Currently-applied outcome filter. UI surfaces this as
    /// a top-right toolbar menu (Apple Mail filter pattern).
    /// Changing the value triggers a full re-fetch from the
    /// first page.
    var filter: ActionOutcomeFilter = .all
    /// The sync's state at the top while the stream is not live (decision 289).
    var syncStatus: PlatformSyncStatus?

    /// Convenience: the accumulated items if any have arrived,
    /// empty list otherwise. Keeps the View `body` from needing
    /// to pattern-match the enum just to read the array.
    var items: [AgentActivityListItem] {
        if case .loaded(let items, _) = listState { return items }
        return []
    }

    /// `true` when the first-page fetch resolved with zero items
    /// AND there's no continuation cursor. Renders the
    /// "no activity yet" empty state instead of a hung Form.
    var isEmpty: Bool {
        if case .loaded(let items, let loadMore) = listState,
           items.isEmpty,
           case .exhausted = loadMore {
            return true
        }
        return false
    }

    /// The empty state's words. Nothing waiting for a decision is good news,
    /// not a filter that missed.
    var emptyTitle: String {
        switch filter {
        case .all: UntranslatedL10n.screenAgentActivityEmptyTitle
        case .pendingConsent: UntranslatedL10n.screenAgentActivityEmptyPendingTitle
        default: UntranslatedL10n.screenAgentActivityEmptyFilteredTitle
        }
    }

    var emptySubtitle: String {
        switch filter {
        case .all: UntranslatedL10n.screenAgentActivityEmptySubtitle
        case .pendingConsent: UntranslatedL10n.screenAgentActivityEmptyPendingSubtitle
        default: UntranslatedL10n.screenAgentActivityEmptyFilteredSubtitle
        }
    }

    /// Sentinel state for the View. `nil` when there's no
    /// sentinel to render (loading / failed first-page / empty /
    /// exhausted); otherwise carries the load-more state.
    var sentinel: LoadMoreState? {
        if case .loaded(let items, let loadMore) = listState, !items.isEmpty {
            switch loadMore {
            case .exhausted: return nil
            default: return loadMore
            }
        }
        return nil
    }
}

// MARK: - View → ViewModel actions

enum AgentActivityScreenViewAction {
    /// The retry button on the first-page error state.
    case retry
    /// Sentinel row appeared on screen (user scrolled to bottom)
    /// — fetch the next page using the current cursor.
    /// No-op if `loadMore` is anything other than `.idle` / `.failed`.
    case loadMore
    /// Outcome filter picker changed. Triggers a full re-fetch
    /// from the first page.
    case selectFilter(ActionOutcomeFilter)
    /// A row was tapped: its approval, else its chat.
    case selectItem(id: String)
}

enum AgentActivityScreenViewModelAction {
    case openRoom(roomID: String)
    case openApproval(approvalID: String)
}

extension ActionOutcomeFilter {
    /// The four the screen offers (step B.6); the rest stay outcome words.
    static let offered: [ActionOutcomeFilter] = [.all, .pendingConsent, .executed, .failed]
}
