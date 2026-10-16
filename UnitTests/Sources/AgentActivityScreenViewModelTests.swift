//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreenViewModelTests.swift`.

@testable import ElementX
import Foundation
import Testing

@MainActor
struct AgentActivityScreenViewModelTests {
    // MARK: - Relative times

    /// A row's time is read against the clock it is given, which the screens
    /// tick while open, so «1 мин. назад» becomes «3 мин. назад» on its own.
    @Test
    func aRowsTimeFollowsTheClock() {
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let item = AgentActivityListItem(id: "a", capabilityName: "messenger.reply_in_room", policyDecision: .allowedDirect,
                                         outcome: .executed, title: "Replied", reason: nil, roomName: nil, createdAt: createdAt)
        let soon = AgentActivityScreen.rowDescription(for: item, now: createdAt.addingTimeInterval(60))
        let later = AgentActivityScreen.rowDescription(for: item, now: createdAt.addingTimeInterval(180))
        #expect(soon == AgentRelativeTime.string(for: createdAt, now: createdAt.addingTimeInterval(60)))
        #expect(later == AgentRelativeTime.string(for: createdAt, now: createdAt.addingTimeInterval(180)))
        #expect(soon != later)
    }

    // MARK: - Empty states

    /// «Ждут вашего решения» with nothing waiting is calm, not a missed filter.
    @Test
    func nothingPendingSaysSoCalmly() {
        let pending = AgentActivityScreenViewState(filter: .pendingConsent, bindings: .init())
        #expect(pending.emptyTitle == UntranslatedL10n.screenAgentActivityEmptyPendingTitle)
        #expect(pending.emptySubtitle == UntranslatedL10n.screenAgentActivityEmptyPendingSubtitle)
        
        let failed = AgentActivityScreenViewState(filter: .failed, bindings: .init())
        #expect(failed.emptyTitle == UntranslatedL10n.screenAgentActivityEmptyFilteredTitle)
        #expect(AgentActivityScreenViewState(bindings: .init()).emptyTitle == UntranslatedL10n.screenAgentActivityEmptyTitle)
    }

    // MARK: - appeared / retry

    @Test
    func appearedAction_loadsAndMapsFirstPage() async throws {
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [Self.executedEntry,
                                                                                              Self.pendingEntry],
                                                                                      nextCursor: nil))

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        let items = viewModel.context.viewState.items
        #expect(items.count == 2)
        #expect(items[0].id == Self.executedEntry.id)
        #expect(items[0].outcome == .executed)
        #expect(items[1].outcome == .pending)
        // Filter defaults to .all on first load.
        #expect(service.listAgentActivityAgentIDFilterCursorLimitReceivedArguments?.filter == .all)
        // First-page fetch sends nil cursor.
        #expect(service.listAgentActivityAgentIDFilterCursorLimitReceivedArguments?.cursor == nil)
        // No more rows → sentinel hidden.
        #expect(viewModel.context.viewState.sentinel == nil)
    }

    @Test
    func appearedAction_skipsRefetchWhenAlreadyLoaded() async throws {
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [Self.executedEntry],
                                                                                      nextCursor: nil))

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.listAgentActivityAgentIDFilterCursorLimitCallsCount == 1)

        // Second appear is a no-op once content is in hand.
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.listAgentActivityAgentIDFilterCursorLimitCallsCount == 1)
    }

    @Test
    func retryAction_refetchesEvenWhenLoaded() async throws {
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [Self.executedEntry],
                                                                                      nextCursor: nil))

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.listAgentActivityAgentIDFilterCursorLimitCallsCount == 1)

        viewModel.context.send(viewAction: .retry)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.listAgentActivityAgentIDFilterCursorLimitCallsCount == 2)
    }

    @Test
    func failedFirstPage_setsFailedStateAndShowsAlert() async throws {
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .failure(.serverError(status: 500))

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .failed = $0 { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.bindings.alertInfo != nil)
    }

    // MARK: - Filter changes

    @Test
    func selectFilter_triggersRefetchWithNewState() async throws {
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [Self.executedEntry],
                                                                                      nextCursor: nil))

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.listAgentActivityAgentIDFilterCursorLimitReceivedArguments?.filter == .all)

        viewModel.context.send(viewAction: .selectFilter(.executed))
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.context.viewState.filter == .executed)
        #expect(service.listAgentActivityAgentIDFilterCursorLimitCallsCount == 2)
        #expect(service.listAgentActivityAgentIDFilterCursorLimitReceivedArguments?.filter == .executed)
        // Cursor reset on filter change.
        #expect(service.listAgentActivityAgentIDFilterCursorLimitReceivedArguments?.cursor == nil)
    }

    @Test
    func selectFilter_sameValueIsNoOp() async throws {
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [Self.executedEntry],
                                                                                      nextCursor: nil))

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(service.listAgentActivityAgentIDFilterCursorLimitCallsCount == 1)

        viewModel.context.send(viewAction: .selectFilter(.all))
        try await Task.sleep(for: .milliseconds(20))
        // No refetch because filter didn't actually change.
        #expect(service.listAgentActivityAgentIDFilterCursorLimitCallsCount == 1)
    }

    // MARK: - Cursor pagination

    @Test
    func loadMore_appendsSecondPageAndPreservesOrder() async throws {
        let service = AgentPlatformServiceMock()
        // Track calls + return different responses per cursor.
        let firstPage: AgentActivityPage = .init(items: [Self.executedEntry,
                                                         Self.pendingEntry],
                                                 nextCursor: "cursor-1")
        let secondPage: AgentActivityPage = .init(items: [Self.deniedEntry],
                                                  nextCursor: nil)
        service.listAgentActivityAgentIDFilterCursorLimitClosure = { _, _, cursor, _ in
            if cursor == nil {
                return .success(firstPage)
            }
            return .success(secondPage)
        }

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        #expect(viewModel.context.viewState.items.count == 2)
        if case .loaded(_, let loadMore) = viewModel.context.viewState.listState {
            if case .idle(let cursor) = loadMore {
                #expect(cursor == "cursor-1")
            } else {
                Issue.record("Expected .idle sentinel after first page; got \(loadMore)")
            }
        } else {
            Issue.record("Expected .loaded after first page")
        }

        viewModel.context.send(viewAction: .loadMore)
        try await Task.sleep(for: .milliseconds(30))

        let combined = viewModel.context.viewState.items
        #expect(combined.count == 3)
        #expect(combined[0].id == Self.executedEntry.id)
        #expect(combined[1].id == Self.pendingEntry.id)
        #expect(combined[2].id == Self.deniedEntry.id)
        #expect(viewModel.context.viewState.sentinel == nil)
    }

    @Test
    func loadMore_isIgnoredWhenSentinelIsLoading() async throws {
        let service = AgentPlatformServiceMock()
        // Slow second-page fetch so the View can fire two `.loadMore`
        // actions before the first one resolves.
        let firstPage: AgentActivityPage = .init(items: [Self.executedEntry], nextCursor: "cursor-1")
        actor CallTracker { var calls = 0; func bump() {
            calls += 1
        } }
        let tracker = CallTracker()
        service.listAgentActivityAgentIDFilterCursorLimitClosure = { _, _, cursor, _ in
            await tracker.bump()
            if cursor == nil { return .success(firstPage) }
            try? await Task.sleep(for: .milliseconds(100))
            return .success(.init(items: [Self.deniedEntry], nextCursor: nil))
        }

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(30))

        // Fire load-more twice in quick succession; the second
        // should be ignored because the first transitioned the
        // sentinel to `.loading`.
        viewModel.context.send(viewAction: .loadMore)
        try await Task.sleep(for: .milliseconds(5))
        viewModel.context.send(viewAction: .loadMore)
        try await Task.sleep(for: .milliseconds(150))

        let calls = await tracker.calls
        // One first-page + one second-page → 2 calls total.
        #expect(calls == 2)
    }

    @Test
    func loadMore_failureTransitionsSentinelToFailed() async throws {
        let service = AgentPlatformServiceMock()
        let firstPage: AgentActivityPage = .init(items: [Self.executedEntry], nextCursor: "cursor-1")
        service.listAgentActivityAgentIDFilterCursorLimitClosure = { _, _, cursor, _ in
            if cursor == nil { return .success(firstPage) }
            return .failure(.serverError(status: 502))
        }

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))
        viewModel.context.send(viewAction: .appeared)
        try await Task.sleep(for: .milliseconds(20))
        viewModel.context.send(viewAction: .loadMore)
        try await Task.sleep(for: .milliseconds(20))

        if case .loaded(let items, let loadMore) = viewModel.context.viewState.listState {
            // First-page items still on screen — load-more
            // failure doesn't clear accumulated items.
            #expect(items.count == 1)
            if case .failed(let cursor) = loadMore {
                #expect(cursor == "cursor-1")
            } else {
                Issue.record("Expected .failed sentinel after load-more failure; got \(loadMore)")
            }
        } else {
            Issue.record("Expected .loaded with sentinel after load-more failure")
        }
    }

    // MARK: - Mapping

    @Test
    func mapItem_carriesOutcomeAndPolicyDecision() {
        let item = AgentActivityScreenViewModel.mapItem(Self.executedEntry, clientProxy: ClientProxyMock(.init()))
        #expect(item.id == Self.executedEntry.id)
        #expect(item.outcome == .executed)
        #expect(item.policyDecision == .allowedDirect)
        #expect(item.capabilityName == "messenger.reply_in_room")
    }

    /// Re-walk R3: the row showed the strategy's internal text
    /// («pre-llm wake-gate skip (Brief 0011 cost optimisation)») and raw
    /// capability ids. It now says what happened and why in the owner's
    /// words, and never carries the free text or a code.
    @Test
    func mapItem_namesTheActionAndReasonNeverTheInternalText() {
        let entry = Self.makeEntry(id: "gate",
                                   capabilityName: "messenger.reply_in_room",
                                   policyDecision: .ignored,
                                   outcome: .ignored,
                                   reasoning: "pre-llm wake-gate skip (Brief 0011 cost optimisation)",
                                   policyReason: "group_room_not_woken")
        let item = AgentActivityScreenViewModel.mapItem(entry, clientProxy: ClientProxyMock(.init()))

        #expect(item.title == UntranslatedL10n.screenAgentActivityActionRepliedInChat)
        #expect(item.reason == UntranslatedL10n.screenAgentActivityReasonGroupRoomNotWoken)
        let shown = [item.title, AgentActivityScreen.rowDescription(for: item), AgentActivityScreen.outcomeLabel(for: item)].joined(separator: "\n")
        #expect(!shown.contains("wake-gate"))
        #expect(!shown.contains("reply_in_room"))
        #expect(!shown.contains("group_room_not_woken"))
    }

    /// Forward tolerance (decision 96): a capability, reason or outcome newer
    /// than this build reads as a neutral word, never as its code.
    @Test
    func mapItem_unknownCodesReadNeutrally() {
        let entry = Self.makeEntry(id: "future",
                                   capabilityName: "studio.shiny_new_thing",
                                   policyDecision: .unknown(rawValue: "future"),
                                   outcome: .unknown(rawValue: "postponed"),
                                   reasoning: "armed tool 01a13cc3-0000 fired",
                                   policyReason: "brand_new_reason")
        let item = AgentActivityScreenViewModel.mapItem(entry, clientProxy: ClientProxyMock(.init()))

        #expect(item.title == UntranslatedL10n.screenAgentActivityActionOther)
        #expect(item.reason == nil)
        #expect(AgentActivityScreen.outcomeLabel(for: item) == UntranslatedL10n.screenAgentActivityOutcomeOther)
        let shown = [item.title, AgentActivityScreen.rowDescription(for: item), AgentActivityScreen.outcomeLabel(for: item)].joined(separator: "\n")
        #expect(!shown.contains("shiny_new_thing"))
        #expect(!shown.contains("brand_new_reason"))
        #expect(!shown.contains("postponed"))
        #expect(!shown.contains("01a13cc3"))
    }

    /// Review: the AI-consent and reply-failed notices go to the person whose
    /// message was dropped (decision 150), not to the owner, so their labels
    /// don't say "you".
    @Test
    func noticesToSomeoneElseDontSayYou() {
        #expect(AgentActivityLabels.action(forCapability: "messenger.notice_ai_consent_needed")
            == UntranslatedL10n.screenAgentActivityActionToldAiNotAllowed)
        #expect(AgentActivityLabels.action(forCapability: "messenger.notice_reply_failed")
            == UntranslatedL10n.screenAgentActivityActionSaidReplyNotSent)
        #expect(!UntranslatedL10n.screenAgentActivityActionToldAiNotAllowed.localizedLowercase.contains("you"))
        #expect(!UntranslatedL10n.screenAgentActivityActionSaidReplyNotSent.localizedLowercase.contains("you"))
    }

    /// Every capability the backend audits today has its own label.
    @Test(arguments: ["messenger.reply_in_room", "messenger.reply_in_owner_dm", "messenger.dm_owner",
                      "messenger.compose_structured_reply", "messenger.summarize_room", "messenger.list_room_members",
                      "messenger.notice_in_room", "messenger.notice_reply_failed", "messenger.notice_ai_consent_needed",
                      "messenger.notice_message_passed_to_owner",
                      "messenger.notice_ai_budget_reached", "messenger.block_sender", "contact.owner_block",
                      "contact.unblock", "contact.owner_unblock", "social.search_agents", "social.read_agent_profile",
                      "social.propose_intro", "memory.remember_about_contact", "memory.recall_about_contact",
                      "schedule.create_action", "schedule.list_actions", "schedule.cancel_action", "voice.answer_call",
                      "voice.leave_call", "voice.switch_mode", "voice.summarize_so_far", "voice.list_recent_calls",
                      "voice.fetch_call_summary", "voice.fetch_call_transcript_window", "session.set_control",
                      "session.save_as_room_default", "tool.arm", "tool.disable", "tool.fire", "interactive.draft",
                      "interactive.studio", "interactive.post"])
    func knownCapabilitiesHaveTheirOwnLabel(_ capability: String) {
        #expect(AgentActivityLabels.action(forCapability: capability) != UntranslatedL10n.screenAgentActivityActionOther)
    }

    /// Every reason code the backend writes today has a label.
    @Test(arguments: ["owner_bypass", "relationship_approved", "capability_always_allowed", "agent_in_target_room",
                      "group_room_trust_implicit", "tool_armed_by_owner", "ai_consent_needed_notice", "ai_budget_notice",
                      "first_contact_with_unknown_visitor", "escalation_rule_match", "capability_always_requires_consent",
                      "block_needs_owner", "unknown_capability", "input_validation_failed", "agent_not_in_room",
                      "owner_not_configured", "contact_not_approved", "wrong_room_kind", "sender_is_owner",
                      "no_contact_relationship", "outside_conversation", "blocked_visitor", "strategy_no_op",
                      "group_room_not_woken", "notice_would_need_consent", "rate_limited", "already_asked_owner",
                      "booth_displacement_voice_master", "relationship_unavailable", "visitor_policy_reply",
                      "message_passed_to_owner_notice"])
    func knownReasonsHaveALabel(_ code: String) {
        #expect(AgentActivityLabels.reason(forPolicyReason: code) != nil)
    }
    
    /// The visitor choices' reasons are the owner's setting, not a request.
    @Test(arguments: ["visitor_policy_reply", "message_passed_to_owner_notice"])
    func visitorPolicyReasonsAreNotARequest(_ code: String) {
        #expect(AgentActivityLabels.reason(forPolicyReason: code) != UntranslatedL10n.screenAgentActivityReasonOwnerBypass)
    }

    // MARK: - Filter wire mapping

    @Test
    func actionOutcomeFilter_wireValue_omitsAllSentinel() {
        #expect(ActionOutcomeFilter.all.wireValue == nil)
        #expect(ActionOutcomeFilter.pendingConsent.wireValue == "pending_consent")
        #expect(ActionOutcomeFilter.executed.wireValue == "executed")
        #expect(ActionOutcomeFilter.failed.wireValue == "failed")
        #expect(ActionOutcomeFilter.declined.wireValue == "declined")
        #expect(ActionOutcomeFilter.cancelled.wireValue == "cancelled")
        #expect(ActionOutcomeFilter.denied.wireValue == "denied")
        #expect(ActionOutcomeFilter.ignored.wireValue == "ignored")
    }

    // MARK: - Outcome / decision parsing

    @Test
    func agentActionOutcome_parsesAllWireValues() {
        #expect(AgentActionOutcome(wire: "pending") == .pending)
        #expect(AgentActionOutcome(wire: "executed") == .executed)
        #expect(AgentActionOutcome(wire: "failed") == .failed)
        #expect(AgentActionOutcome(wire: "declined") == .declined)
        #expect(AgentActionOutcome(wire: "cancelled") == .cancelled)
        #expect(AgentActionOutcome(wire: "denied") == .denied)
        #expect(AgentActionOutcome(wire: "ignored") == .ignored)
        // Future-compat: unknown tag degrades gracefully.
        if case .unknown(let raw) = AgentActionOutcome(wire: "future_tag") {
            #expect(raw == "future_tag")
        } else {
            Issue.record("Expected .unknown for future tag")
        }
    }

    @Test
    func agentActionPolicyDecision_parsesAllWireValues() {
        #expect(AgentActionPolicyDecision(wire: "allowed_direct") == .allowedDirect)
        #expect(AgentActionPolicyDecision(wire: "requires_owner_consent") == .requiresOwnerConsent)
        #expect(AgentActionPolicyDecision(wire: "denied") == .denied)
        #expect(AgentActionPolicyDecision(wire: "ignored") == .ignored)
        if case .unknown(let raw) = AgentActionPolicyDecision(wire: "future_tag") {
            #expect(raw == "future_tag")
        } else {
            Issue.record("Expected .unknown for future tag")
        }
    }

    // MARK: - Empty state

    @Test
    func emptyFirstPage_marksEmpty() async throws {
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [], nextCursor: nil))

        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1",
                                                     agentPlatformService: service,
                                                     clientProxy: ClientProxyMock(.init()))

        let deferred = deferFulfillment(viewModel.context.observe(\.viewState.listState)) {
            if case .loaded(let items, _) = $0, items.isEmpty { return true }
            return false
        }
        viewModel.context.send(viewAction: .appeared)
        try await deferred.fulfill()

        #expect(viewModel.context.viewState.isEmpty)
    }

    // MARK: - Fixtures

    static let executedEntry = makeEntry(id: "row-executed",
                                         capabilityName: "messenger.reply_in_room",
                                         policyDecision: .allowedDirect,
                                         outcome: .executed,
                                         reasoning: "Owner relationship approved; reply delivered.")

    static let pendingEntry = makeEntry(id: "row-pending",
                                        capabilityName: "messenger.send_owner_dm",
                                        policyDecision: .requiresOwnerConsent,
                                        outcome: .pending,
                                        reasoning: "First contact with unknown visitor requires owner consent.")

    static let deniedEntry = makeEntry(id: "row-denied",
                                       capabilityName: "messenger.reply_in_room",
                                       policyDecision: .denied,
                                       outcome: .denied,
                                       reasoning: "Visitor is on the blocked list.")

    static func makeEntry(id: String,
                          capabilityName: String,
                          policyDecision: AgentActionPolicyDecision,
                          outcome: AgentActionOutcome,
                          reasoning: String,
                          policyReason: String = "fixture") -> AgentActivityEntry {
        AgentActivityEntry(id: id,
                           agentID: "agent-1",
                           roomID: "!example:spiral.md",
                           capabilityName: capabilityName,
                           inputRedacted: [:],
                           reasoningSummary: reasoning,
                           policyDecision: policyDecision,
                           policyReason: policyReason,
                           approvalID: nil,
                           longFlowID: nil,
                           outcome: outcome,
                           outcomeEventID: outcome == .executed ? "$event:spiral.md" : nil,
                           createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                           resolvedAt: outcome == .pending ? nil : Date(timeIntervalSince1970: 1_700_000_010))
    }
    
    // MARK: - Relative times read as the past
    
    @Test
    func relativeTimesAreNeverNegative() {
        let now = Date(timeIntervalSince1970: 1_791_633_600)
        for identifier in ["ru", "uk", "en"] {
            let locale = Locale(identifier: identifier)
            let past = AgentRelativeTime.string(for: now.addingTimeInterval(-300), now: now, locale: locale)
            #expect(!past.hasPrefix("-"), "\(identifier): \(past)")
            // A time a little ahead of this device's clock reads as now, not as "in 2 min".
            let skewed = AgentRelativeTime.string(for: now.addingTimeInterval(120), now: now, locale: locale)
            #expect(skewed == AgentRelativeTime.string(for: now, now: now, locale: locale))
        }
        #expect(AgentRelativeTime.string(for: now.addingTimeInterval(-300), now: now, locale: Locale(identifier: "ru")).contains("назад"))
    }
    
    // MARK: - Step B.6
    
    @Test
    func theScreenOffersFourFilters() {
        #expect(ActionOutcomeFilter.offered == [.all, .pendingConsent, .executed, .failed])
    }
    
    /// G5: a row opens its approval first, else a chat this device has.
    @Test
    func aRowOpensItsApprovalElseItsChat() async throws {
        var withApproval = Self.makeEntry(id: "row-approval", capabilityName: "messenger.reply_in_room",
                                          policyDecision: .requiresOwnerConsent, outcome: .pending, reasoning: "x")
        withApproval = AgentActivityEntry(id: withApproval.id, agentID: withApproval.agentID, roomID: withApproval.roomID,
                                          capabilityName: withApproval.capabilityName, inputRedacted: [:], reasoningSummary: "x",
                                          policyDecision: withApproval.policyDecision, policyReason: "fixture", approvalID: "approval-1",
                                          longFlowID: nil, outcome: .pending, outcomeEventID: nil, createdAt: withApproval.createdAt, resolvedAt: nil)
        let service = AgentPlatformServiceMock()
        service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: [withApproval, Self.executedEntry], nextCursor: nil))
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { $0 == "!example:spiral.md" ? .mock(id: $0, name: "Book club") : nil }
        let viewModel = AgentActivityScreenViewModel(agentID: "agent-1", agentPlatformService: service, clientProxy: clientProxy)
        
        let loaded = deferFulfillment(viewModel.context.observe(\.viewState.listState)) { if case .loaded = $0 { true } else { false } }
        viewModel.context.send(viewAction: .appeared)
        try await loaded.fulfill()
        
        let approval = deferFulfillment(viewModel.actionsPublisher) { if case .openApproval("approval-1") = $0 { true } else { false } }
        viewModel.context.send(viewAction: .selectItem(id: "row-approval"))
        try await approval.fulfill()
        
        let room = deferFulfillment(viewModel.actionsPublisher) { if case .openRoom("!example:spiral.md") = $0 { true } else { false } }
        viewModel.context.send(viewAction: .selectItem(id: Self.executedEntry.id))
        try await room.fulfill()
    }
    
    /// A visitor's chat the owner isn't in has nothing to open.
    @Test
    func aChatThisDeviceDoesntHaveDoesntOpen() {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierClosure = { _ in nil }
        let item = AgentActivityScreenViewModel.mapItem(Self.executedEntry, clientProxy: clientProxy)
        #expect(item.roomID == nil)
        #expect(item.approvalID == nil)
    }
    
    /// An action the agent runs on its own is not labelled «Вы попросили».
    @Test
    func anAutomaticActionIsNotWhatYouAskedFor() {
        #expect(AgentActivityLabels.reason(forPolicyReason: "owner_bypass", capabilityName: "voice.answer_call") == nil)
        #expect(AgentActivityLabels.reason(forPolicyReason: "owner_bypass", capabilityName: "messenger.dm_owner") == nil)
        // The «tools turned on» notice the agent posts after an arm, and the
        // one telling a person their message went to the owner.
        #expect(AgentActivityLabels.reason(forPolicyReason: "owner_bypass", capabilityName: "messenger.notice_in_room") == nil)
        #expect(AgentActivityLabels.reason(forPolicyReason: "owner_bypass", capabilityName: "messenger.notice_message_passed_to_owner") == nil)
        #expect(AgentActivityLabels.reason(forPolicyReason: "owner_bypass", capabilityName: "tool.arm")
            == UntranslatedL10n.screenAgentActivityReasonOwnerBypass)
        #expect(AgentActivityLabels.reason(forPolicyReason: "owner_bypass", capabilityName: "schedule.create_action")
            == UntranslatedL10n.screenAgentActivityReasonOwnerBypass)
        #expect(AgentActivityLabels.reason(forPolicyReason: "relationship_approved", capabilityName: "messenger.dm_owner")
            == UntranslatedL10n.screenAgentActivityReasonRelationshipApproved)
    }
}
