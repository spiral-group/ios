//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 387; Brief 0085, question 403): the pages of the call's "Assistants" sheet, in
// the call's glass (L5, `NativeCallAssistantsGlass`). The root is your own assistant: the four job buttons, then one
// row or one question under them — the language it translates into (L1), Stop, a refusal and its one way out, or the
// recording's confirmation in place — and at the bottom "In the call · N more" for everyone else's. "New translation"
// (L4) is the root opened from the 文A menu's "+". Someone else's assistant is one row from your side, its page the same
// four buttons read-only and what they mean for you. No listener counts anywhere (403, Q3).

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

// MARK: - Your assistant (the root)

/// Where your own assistant stands, for the root's header and content.
enum NativeCallOwnAssistantStage: Equatable {
    /// The platform hasn't answered yet: placeholders at the final size.
    case loading
    /// The platform never answered.
    case unavailable
    case inCall(NativeCallAgentPresentation.Agent)
    /// Accepted and on its way, or the add answered before its session is read (board A of 401).
    case joining(mxid: String, control: NativeCallAgentPresentation.Control?)
    /// Not in the call: a tap on a button brings it.
    case notInCall(NativeAgentCenterCandidate)
    /// This person has no assistant.
    case none

    init(_ context: NativeCallScreenViewModel.Context) {
        let agents = context.viewState.agents
        let layout = NativeCallAssistantsLayout(panel: agents.panel)
        switch layout.content {
        case .placeholders:
            self = .loading
            return
        case .nothing:
            self = .unavailable
            return
        case .ready:
            break
        }
        let panel = agents.panel
        if let agent = agents.ownAgents.first {
            self = .inCall(agent)
        } else if let control = (agents.joining + agents.removing).first(where: { $0.canControl || panel.ownAgentMxids.contains($0.agentMxid) }) {
            self = .joining(mxid: control.agentMxid, control: control)
        } else if let candidate = panel.candidates.first(where: { candidate in
            panel.acceptedAttaches.contains(candidate.id)
                && context.viewState.agentActionsInFlight.contains(.add(agentID: candidate.id))
                && !agents.agents.contains { $0.mxid == candidate.mxid }
        }) {
            self = .joining(mxid: candidate.mxid, control: nil)
        } else if let candidate = panel.candidates.first(where: { $0.id == context.viewState.pickedAssistantID }) ?? panel.candidates.first {
            self = .notInCall(candidate)
        } else {
            self = .none
        }
    }
}

/// L6: the own assistant's "…" menu — its profile and your limit always, removing it only while it is in the call.
enum NativeCallOwnAssistantMenuItem: Hashable {
    case profile
    case limit
    case removeFromCall

    static func items(isRemovableFromCall: Bool) -> [Self] {
        [.profile, .limit] + (isRemovableFromCall ? [.removeFromCall] : [])
    }
}

/// The sheet's root: your assistant's header, its buttons and what goes under them, then everyone else's row.
struct NativeCallOwnAssistantPage: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    @Binding var path: [NativeCallAssistantsRoute]
    let onLearnMore: () -> Void

    @State private var isRemoveConfirmationPresented = false
    /// Ticks once a second while your assistant is on its way, so "Still joining…" comes on time (N8).
    @State private var now = Date()

    /// N8: join time is not measured yet; about 20 s, then the status says it's still on its way.
    static let stillJoiningAfter: TimeInterval = 20

    private var agents: NativeCallAgentPresentation {
        context.viewState.agents
    }

    private var panel: NativeCallAgentPresentation.Panel {
        agents.panel
    }

    private var stage: NativeCallOwnAssistantStage {
        NativeCallOwnAssistantStage(context)
    }

    private var isCreating: Bool {
        // The private call's translation is the pocket interpreter: its one pick is the neighbour's language (L11).
        guard context.isCreatingTranslation, !context.viewState.isAssistantPage else { return false }
        if case .inCall(let agent) = stage { return !agent.shown.isTranslating }
        return true
    }

    var body: some View {
        let stage = stage
        NativeCallSheetPage {
            header(stage)
        } content: {
            Group {
                switch stage {
                case .loading:
                    placeholders
                case .unavailable:
                    unavailable
                case .inCall(let agent):
                    inCall(agent)
                case .joining(let mxid, let control):
                    joining(mxid: mxid, control: control)
                case .notInCall(let candidate):
                    notInCall(candidate)
                case .none:
                    EmptyView()
                }
                if stage != .loading, stage != .unavailable, !isCreating, !isCardInPlace {
                    othersRow
                }
            }
            .transition(.opacity)
        }
        .animation(NativeCallAssistantsMotion.change, value: stage)
        .animation(NativeCallAssistantsMotion.change, value: context.assistantConfirmation)
        .animation(NativeCallAssistantsMotion.change, value: context.isCreatingTranslation)
        .animation(NativeCallAssistantsMotion.change, value: context.viewState.translation)
        .animation(NativeCallAssistantsMotion.change, value: context.viewState.recordingCover)
        .onChange(of: context.assistantConfirmation) { _, confirmation in
            // Question 404: the card replaces the buttons without moving focus, so VoiceOver hears what it says.
            if let card = card(confirmation) {
                AccessibilityNotification.Announcement("\(card.title). \(card.detail ?? "")").post()
            }
        }
        .confirmationDialog(removeConfirmationMessage ?? "", isPresented: $isRemoveConfirmationPresented, titleVisibility: .visible) {
            Button(UntranslatedL10n.screenNativeCallAssistantsRemove, role: .destructive) {
                if let control = ownAgent?.control { context.send(viewAction: .removeAgent(sessionID: control.sessionID)) }
            }
        }
        .task(id: isJoining) {
            while isJoining, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
    }

    // MARK: Header

    private func header(_ stage: NativeCallOwnAssistantStage) -> some View {
        let status = status(stage)
        return NativeCallSheetHeader(title: isCreating ? UntranslatedL10n.screenNativeCallAssistantsNewTranslation : title(stage),
                                     status: status?.text,
                                     isStatusCritical: status?.isCritical ?? false,
                                     isLoading: stage == .loading,
                                     onClose: { context.send(viewAction: .dismissAgentCenter) },
                                     leading: { avatar(stage) },
                                     accessory: {
                                         // L6: the limits are always one tap away, in or out of the call.
                                         if let mxid = ownMxid(stage), !isCreating {
                                             menu(mxid: mxid, items: menuItems(stage))
                                         }
                                     })
    }

    @ViewBuilder
    private func avatar(_ stage: NativeCallOwnAssistantStage) -> some View {
        let mxid: String? = switch stage {
        case .inCall(let agent): agent.mxid
        case .joining(let mxid, _): mxid
        case .notInCall(let candidate): candidate.mxid
        case .loading, .unavailable, .none: nil
        }
        if let mxid {
            NativeCallSheetAvatar(mxid: mxid,
                                  name: context.viewState.memberProfiles[mxid]?.displayName ?? panel.candidates.first { $0.mxid == mxid }?.displayName ?? mxid,
                                  url: context.viewState.memberProfiles[mxid]?.avatarURL ?? panel.candidates.first { $0.mxid == mxid }?.avatarURL,
                                  mediaProvider: context.mediaProvider)
        } else {
            Circle()
                .fill(Color.compound.bgSubtleSecondary)
                .frame(width: SpiralAvatarSize.small, height: SpiralAvatarSize.small)
                .spiralLoadingSlot(stage == .loading, label: L10n.commonLoading)
                .accessibilityHidden(true)
        }
    }

    /// "Your assistant", or its own name when the owner has several (D11).
    private func title(_ stage: NativeCallOwnAssistantStage) -> String {
        guard panel.ownAgentMxids.count > 1 else { return UntranslatedL10n.screenNativeCallAssistantsYourAssistant }
        let mxid: String? = switch stage {
        case .inCall(let agent): agent.mxid
        case .joining(let mxid, _): mxid
        case .notInCall(let candidate): candidate.mxid
        case .loading, .unavailable, .none: nil
        }
        guard let mxid else { return UntranslatedL10n.screenNativeCallAssistantsYourAssistant }
        return context.viewState.memberProfiles[mxid]?.displayName
            ?? panel.candidates.first { $0.mxid == mxid }?.displayName
            ?? UntranslatedL10n.screenNativeCallAssistantsYourAssistant
    }

    /// One line on what it does, or why it can't (L5): «Не в звонке», «Идёт в звонок…», «Переводит на украинский».
    private func status(_ stage: NativeCallOwnAssistantStage) -> (text: String, isCritical: Bool)? {
        if isCreating, stage != .loading {
            return (UntranslatedL10n.screenNativeCallAssistantsNewTranslationDetail, false)
        }
        switch stage {
        case .loading:
            return nil
        case .unavailable:
            return (UntranslatedL10n.screenNativeCallAssistantsUnavailable, false)
        case .none:
            return (UntranslatedL10n.screenNativeCallAssistantsNoneOfYourOwn, false)
        case .notInCall(let candidate):
            return (candidate.isPaused ? UntranslatedL10n.screenNativeCallAssistantsStatusPaused : UntranslatedL10n.screenNativeCallAssistantsNotInCall, false)
        case .joining(_, let control):
            if control?.isEndRequested == true { return (UntranslatedL10n.screenNativeCallAssistantsLeaving, false) }
            if isRinging { return (UntranslatedL10n.screenNativeCallAssistantsJoinsWhenAnswered, false) }
            return (isStillJoining ? UntranslatedL10n.screenNativeCallAssistantsStillJoining : UntranslatedL10n.screenNativeCallAssistantsJoining, false)
        case .inCall(let agent):
            if agent.shown.presence == .leaving { return (UntranslatedL10n.screenNativeCallAssistantsLeaving, false) }
            if pauseLine(agent) != nil { return (UntranslatedL10n.screenNativeCallAssistantsStatusLimit, true) }
            if let line = NativeCallAssistantsCopy.translationStatus(isSyncing: agent.control?.translation.isSyncing == true,
                                                                     isStandby: agent.shown.isStandby,
                                                                     isNothingToTranslate: isNothingToTranslate(agent)) {
                return (line, false)
            }
            if context.viewState.isAssistantPage, agent.shown.isTranslating {
                return (UntranslatedL10n.screenNativeCallAssistantsStatusBothWays, false)
            }
            if agent.live.stoppedReason == .ownerLeft {
                return (UntranslatedL10n.screenNativeCallAssistantsStatusOwnerLeft, false)
            }
            return (NativeCallAssistantsCopy.status(agent.shown, catalog: panel.catalog), false)
        }
    }

    /// Its translation into a language everyone else already speaks: standing by covers nobody's lanes, there are none.
    private func isNothingToTranslate(_ agent: NativeCallAgentPresentation.Agent) -> Bool {
        guard let language = agent.control?.translation.effective.forLanguage else { return false }
        return context.viewState.translation.isNothingToTranslate(into: language)
    }

    /// The assistant the header names, whenever the sheet shows one of your own.
    private func ownMxid(_ stage: NativeCallOwnAssistantStage) -> String? {
        switch stage {
        case .inCall(let agent): agent.mxid
        case .joining(let mxid, _): mxid
        case .notInCall(let candidate): candidate.mxid
        case .loading, .unavailable, .none: nil
        }
    }

    private func menuItems(_ stage: NativeCallOwnAssistantStage) -> [NativeCallOwnAssistantMenuItem] {
        let isRemovable = if case .inCall(let agent) = stage {
            agent.control != nil && agent.shown.presence != .leaving && !context.viewState.isAssistantPage
        } else {
            false
        }
        return NativeCallOwnAssistantMenuItem.items(isRemovableFromCall: isRemovable)
    }

    /// The rare actions (L6): the assistant's profile and your limit, together; removing it from the call in a
    /// section of its own, only while it is in the call (never on its own private call).
    private func menu(mxid: String, items: [NativeCallOwnAssistantMenuItem]) -> some View {
        Menu {
            Section {
                ForEach(items.filter { $0 != .removeFromCall }, id: \.self) { item in
                    switch item {
                    case .profile:
                        Button {
                            context.send(viewAction: .showAgentProfile(agentMxid: mxid))
                        } label: {
                            Label(UntranslatedL10n.screenNativeCallAssistantsMenuProfile, icon: \.user)
                        }
                    case .limit:
                        Button {
                            context.send(viewAction: .showAgentLimit(agentMxid: mxid))
                        } label: {
                            Label(UntranslatedL10n.screenNativeCallAssistantsMyLimit, systemImage: "gauge.with.dots.needle.33percent")
                        }
                    case .removeFromCall:
                        EmptyView()
                    }
                }
            }
            if items.contains(.removeFromCall), let control = ownAgent?.control {
                Section {
                    Button(role: .destructive) {
                        if removeConfirmationMessage != nil {
                            isRemoveConfirmationPresented = true
                        } else {
                            context.send(viewAction: .removeAgent(sessionID: control.sessionID))
                        }
                    } label: {
                        Label(UntranslatedL10n.screenNativeCallAssistantsRemoveFromCall, icon: \.leave)
                    }
                }
            }
        } label: {
            if isInFlight(.remove) {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                NativeCallSheetRoundGlyph(systemImage: "ellipsis")
            }
        }
        .accessibilityLabel(UntranslatedL10n.a11yNativeCallAssistantsMore)
    }

    // MARK: Loading and unavailable

    /// The root's shape — four buttons and the translation's rows — so the answer lands in place.
    private var placeholders: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            NativeCallAssistantDockView(state: NativeCallAssistantDockState(.init()), isInteractive: false) { _ in }
                .spiralLoadingSlot(true, label: L10n.commonLoading)
            translationPlaceholderRows
        }
    }

    /// A placeholder for each of the translation's setting rows: one between people, two in the private call.
    private var translationPlaceholderRows: some View {
        ForEach(0..<translationSettingRow.rowCount, id: \.self) { _ in
            NativeCallSheetPlaceholderRow()
        }
    }

    private var unavailable: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            NativeCallSheetNotice(systemImage: "wifi.exclamationmark",
                                  title: UntranslatedL10n.screenNativeCallAssistantsUnavailable,
                                  detail: UntranslatedL10n.screenNativeCallAssistantsUnavailableDetail)
            NativeCallSheetSecondaryButton(title: UntranslatedL10n.screenNativeCallAssistantsTryAgain, isWaiting: panel.isLoading) {
                context.send(viewAction: .reloadAgentCenter)
            }
        }
    }

    // MARK: In the call (1.3, 1.4, 1.5, 2.4, 5.1)

    private var ownAgent: NativeCallAgentPresentation.Agent? {
        if case .inCall(let agent) = stage { return agent }
        return nil
    }

    /// L8 A: an inline confirmation takes the place of the buttons and the rows under them, in the same frame; the
    /// header stays. Answered or cancelled, they come back. Question 404's card (layout C) does the same.
    @ViewBuilder
    private func inCall(_ agent: NativeCallAgentPresentation.Agent) -> some View {
        if context.assistantConfirmation == .recording {
            recordingConfirmation
        } else if let card = card(context.assistantConfirmation) {
            noticeCard(card)
        } else {
            VStack(spacing: CompoundDesignTokens.space3X) {
                inCallJobs(agent)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func inCallJobs(_ agent: NativeCallAgentPresentation.Agent) -> some View {
        let control = agent.control
        let dock = dock(agent)
        NativeCallAssistantDockView(state: dock, isInteractive: control != nil && agent.shown.presence == .present, coverBadge: coverBadge, onTap: tap)
        if let control {
            NativeCallInlineError(scope: .session(control.sessionID, .remove), context: context)
        }
        if let refusal = refusal(agent) {
            NativeCallSheetNotice(systemImage: "exclamationmark.circle", title: refusal.reason, detail: nil)
            NativeCallSheetSecondaryButton(title: UntranslatedL10n.screenNativeCallAssistantsTryAgain) { tap(refusal.job) }
        } else if let pauseLine = pauseLine(agent) {
            // L5 2.4: your translation stopped for everyone on your limit.
            NativeCallSheetNotice(systemImage: "exclamationmark.circle",
                                  title: UntranslatedL10n.screenNativeCallAssistantsLimitTitle,
                                  detail: pauseLine)
            NativeCallSheetSecondaryButton(title: UntranslatedL10n.screenNativeCallAssistantsMyLimit) {
                context.send(viewAction: .showAgentLimit(agentMxid: agent.mxid))
            }
        } else if agent.shown.isConversationActive, !context.viewState.isAssistantPage {
            // L5 1.4: one line instead of a card. Not in the private call, where translation isn't off while it talks:
            // its pair, «Я говорю» and «Человек рядом», is there instead, and picking the neighbour's language switches (L11).
            NativeCallSheetCaption(text: UntranslatedL10n.screenNativeCallAssistantsTalkCaption)
        } else if isCreating {
            newTranslation
        } else {
            translationRow
            if agent.shown.isTranslating, let control {
                stopRow(control, isStandby: agent.shown.isStandby)
            }
        }
        if !agent.shown.isConversationActive, !isCardInPlace, let delivery = delivery(control) {
            NativeCallSheetCaption(text: delivery)
        }
    }

    private func dock(_ agent: NativeCallAgentPresentation.Agent) -> NativeCallAssistantDockState {
        let control = agent.control
        var facts = NativeCallAssistantDockState.Facts(isTranslating: agent.shown.isTranslating,
                                                       isTakingNotes: agent.shown.isSummaryArmed,
                                                       isRecording: agent.shown.isRecording,
                                                       isTalking: agent.shown.isConversationActive,
                                                       isRecordingStopped: control?.recording.isStopped == true
                                                           || control.map { NativeCallAssistantsCopy.isDelivering($0.recording) } == true)
        if let control {
            facts.busy = Set(NativeCallAssistantJob.allCases.filter { context.viewState.agentActionsInFlight.contains(.session(control.sessionID, $0.row)) })
        }
        facts.refused = refusal(agent)?.job ?? (pauseLine(agent) == nil ? nil : .translation)
        facts.pending = context.viewState.switchingAssistantJob ?? pendingJob
        facts.switchesTalkAndTranslation = context.viewState.isAssistantPage
        facts.isTranslationSyncing = control?.translation.isSyncing == true
        facts.isTalkUnavailable = control.map { !$0.conversation.isAvailable } ?? false
        facts.recordingCover = context.viewState.recordingCover?.phase
        return NativeCallAssistantDockState(facts)
    }

    /// The job waiting on a question (recording) or on "Start translation" (2.1).
    private var pendingJob: NativeCallAssistantJob? {
        if context.assistantConfirmation == .recording { return .recording }
        return isCreating ? .translation : nil
    }

    /// The `call_translation` cap stopped translation (L5 2.4).
    private func pauseLine(_ agent: NativeCallAgentPresentation.Agent) -> String? {
        agent.control?.translation.pause.map { AgentLimitWording.categoryPauseLine(.callTranslation, $0) }
    }

    /// A refused write, on the button that asked (audit F8).
    private func refusal(_ agent: NativeCallAgentPresentation.Agent) -> (job: NativeCallAssistantJob, reason: String)? {
        guard let control = agent.control, let error = panel.lastError else { return nil }
        guard let job = NativeCallAssistantJob.allCases.first(where: { panel.lastErrorScope == .session(control.sessionID, $0.row) }) else { return nil }
        return (job, NativeCallAssistantsCopy.errorTitle(error, context: context))
    }

    /// Where a stopped recording or the notes went, as the backend says.
    private func delivery(_ control: NativeCallAgentPresentation.Control?) -> String? {
        guard let control else { return nil }
        if control.recording.isStopped || NativeCallAssistantsCopy.isDelivering(control.recording) {
            return NativeCallAssistantsCopy.recordingDelivery(control.recording) ?? UntranslatedL10n.screenNativeCallAssistantsRecordingStopped
        }
        return NativeCallAssistantsCopy.notesDelivery(control.summary)
    }

    private func tap(_ job: NativeCallAssistantJob) {
        context.send(viewAction: .tapAssistantJob(job))
    }

    // MARK: On its way (1.2, 3.4)

    private var isJoining: Bool {
        if case .joining = stage { return true }
        return false
    }

    private var isRinging: Bool {
        context.viewState.callState != .connected
    }

    private var isStillJoining: Bool {
        guard !isRinging, case .joining(_, let control?) = stage, let started = panel.joinStartedAt[control.sessionID] else { return false }
        return now.timeIntervalSince(started) >= Self.stillJoiningAfter
    }

    @ViewBuilder
    private func joining(mxid: String, control: NativeCallAgentPresentation.Control?) -> some View {
        let sent = context.viewState.attachesSent[mxid]
        NativeCallAssistantDockView(state: NativeCallAssistantDockState(.init(pending: sentJob(sent, control: control))), isInteractive: false) { _ in }
        if sent?.translation != nil || control?.translation.isOn == true {
            translationRow
        }
        // L5 1.2 and 3.4: one way back — the call is undone, so "Отменить".
        NativeCallSheetSecondaryButton(title: UntranslatedL10n.screenNativeCallAssistantsCancelJoin,
                                       isWaiting: control.map { context.viewState.agentActionsInFlight.contains(.session($0.sessionID, .remove)) || $0.isEndRequested } ?? true) {
            if let control { context.send(viewAction: .cancelAgentJoin(sessionID: control.sessionID)) }
        }
        if let control {
            NativeCallInlineError(scope: .session(control.sessionID, .remove), context: context)
        }
    }

    /// The job it was called for: the one button ringed while it comes.
    private func sentJob(_ sent: VoiceAttachParams?, control: NativeCallAgentPresentation.Control?) -> NativeCallAssistantJob? {
        if sent?.translation != nil || control?.translation.isOn == true { return .translation }
        if sent?.conversation == true { return .conversation }
        if sent?.recording ?? control?.recording.isEnabled == true { return .recording }
        if sent?.summary ?? control?.summary.isEnabled == true { return .summary }
        return nil
    }

    // MARK: Not in the call (1.1, 2.1, 3.1, 3.2)

    private func notInCall(_ candidate: NativeAgentCenterCandidate) -> some View {
        let failure = panel.startFailure(for: candidate)
        let isAdding = panel.candidates.contains { context.viewState.agentActionsInFlight.contains(.add(agentID: $0.id)) }
        let isChecking = panel.isJoinCheckPending(candidate)
        var facts = NativeCallAssistantDockState.Facts(block: context.viewState.translation.block)
        if isAdding, let job = lastJob {
            facts.busy = [job]
        }
        facts.pending = pendingJob
        facts.recordingCover = context.viewState.recordingCover?.phase
        return Group {
            if context.assistantConfirmation == .recording {
                recordingConfirmation
            } else if let card = card(context.assistantConfirmation) {
                noticeCard(card)
            } else {
                notInCallJobs(facts: facts, failure: failure, candidate: candidate, isAdding: isAdding, isChecking: isChecking)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func notInCallJobs(facts: NativeCallAssistantDockState.Facts,
                               failure: NativeAgentCenterJoinFailure?,
                               candidate: NativeAgentCenterCandidate,
                               isAdding: Bool,
                               isChecking: Bool) -> some View {
        let dock = NativeCallAssistantDockState(facts)
        VStack(spacing: CompoundDesignTokens.space3X) {
            NativeCallAssistantDockView(state: dock, isInteractive: !isAdding && !isChecking, coverBadge: coverBadge, onTap: tap)
                .spiralLoadingSlot(isChecking, label: L10n.commonLoading)
            if isChecking {
                // Whether it can come is still being asked: the rows' placeholders, never a start that's refused next.
                translationPlaceholderRows
            } else if let failure {
                blocked(failure, candidate: candidate)
            } else if isCreating {
                newTranslation
            } else {
                translationRow
            }
        }
    }

    /// The job the add in flight asked for.
    private var lastJob: NativeCallAssistantJob? {
        guard let sent = panel.candidates.lazy.compactMap({ context.viewState.attachesSent[$0.mxid] }).first else { return nil }
        return sentJob(sent, control: nil)
    }

    /// L5 3.1, 3.2: why it can't come, in one block, and its one way out — the main action blue, a lesser one glass.
    @ViewBuilder
    private func blocked(_ failure: NativeAgentCenterJoinFailure, candidate: NativeAgentCenterCandidate) -> some View {
        let copy = NativeCallAssistantsCopy.joinFailure(failure, context: context)
        NativeCallSheetNotice(systemImage: copy.symbol, title: copy.title, detail: copy.detail)
        NativeCallInlineError(scope: .agent(candidate.id), context: context)
        if let next = nextStep(failure, candidate: candidate) {
            let isWaiting = context.viewState.agentActionsInFlight.contains(.resume(agentID: candidate.id))
            if next.isMain {
                NativeCallSheetPrimaryButton(title: next.title, isWaiting: isWaiting, action: next.action)
            } else {
                NativeCallSheetSecondaryButton(title: next.title, isWaiting: isWaiting, action: next.action)
            }
        }
    }

    /// A refusal's one way out; the main one (allow, resume) is the blue action.
    private struct NextStep {
        let title: String
        let isMain: Bool
        let action: () -> Void
    }

    private func nextStep(_ failure: NativeAgentCenterJoinFailure, candidate: NativeAgentCenterCandidate) -> NextStep? {
        switch failure {
        case .paused:
            NextStep(title: UntranslatedL10n.screenNativeCallAssistantsResume, isMain: true) { context.send(viewAction: .resumeAgent(agentID: candidate.id)) }
        case .aiConsentOwner:
            NextStep(title: UntranslatedL10n.screenNativeCallAssistantsAllowAi, isMain: true) { context.send(viewAction: .allowAI) }
        case .aiConsentRoom:
            NextStep(title: UntranslatedL10n.screenNativeCallAssistantsLearnMore, isMain: false, action: onLearnMore)
        case .askToJoin:
            NextStep(title: UntranslatedL10n.screenNativeCallAssistantsCopyId, isMain: false) { UIPasteboard.general.string = candidate.mxid }
        case .budgetReached, .categoryPaused:
            NextStep(title: UntranslatedL10n.screenNativeCallAssistantsMyLimit, isMain: false) { context.send(viewAction: .showAgentLimit(agentMxid: candidate.mxid)) }
        case .failed, .cannotJoinCalls, .needsUpdate:
            nil
        }
    }

    // MARK: Rows

    private var translationSettingRow: NativeCallTranslationSettingRow {
        NativeCallTranslationSettingRow(isPrivateCall: context.viewState.isAssistantPage)
    }

    /// The translation's setting rows: «Перевод на · …» in a call between people; in the private call the pocket
    /// interpreter's pair, «Я говорю · …» over «Человек рядом · …» (L11, S1).
    @ViewBuilder
    private var translationRow: some View {
        switch translationSettingRow {
        case .translateInto:
            languageRow
        case .pocketPair:
            mySpokenLanguageRow
            neighbourRow
        }
    }

    /// L1: «Перевод на · Украинский ›» — the language you hear, which your assistant translates into. Shown before it
    /// starts too, so the language is picked first.
    private var languageRow: some View {
        NativeCallSheetRow(icon: "translate",
                           title: UntranslatedL10n.screenNativeCallAssistantsTranslateInto,
                           value: NativeCallTranslationCopy.languageTitle(context.viewState.myLanguage),
                           showsChevron: true) {
            path.append(.myLanguage)
        }
    }

    /// S1: the pocket interpreter's own side — "my language", what you speak and hear — on the same page as «Перевод на».
    private var mySpokenLanguageRow: some View {
        NativeCallSheetRow(icon: "person.wave.2",
                           title: UntranslatedL10n.screenNativeCallAssistantsISpeak,
                           value: NativeCallTranslationCopy.languageTitle(context.viewState.myLanguage),
                           showsChevron: true) {
            path.append(.myLanguage)
        }
    }

    /// L5 5.1: the pocket interpreter's other side; a stored neighbour that is my own language isn't a pick (S1).
    private var neighbourRow: some View {
        NativeCallSheetRow(icon: "person",
                           title: UntranslatedL10n.screenNativeCallAssistantsNeighbour,
                           value: context.viewState.neighbourLanguage
                               .flatMap { $0 == context.viewState.myLanguage ? nil : $0 }
                               .map(NativeCallTranslationCopy.languageTitle),
                           showsChevron: true) {
            path.append(.neighbourLanguage)
        }
    }

    /// «Остановить перевод»; «Остановить» while it stands by (row 10): it isn't translating yet.
    private func stopRow(_ control: NativeCallAgentPresentation.Control, isStandby: Bool) -> some View {
        NativeCallSheetRow(icon: "stop",
                           title: isStandby ? UntranslatedL10n.screenNativeCallAssistantsStopStandby : UntranslatedL10n.screenNativeCallAssistantsStopTranslation,
                           role: .destructive,
                           isWaiting: context.viewState.agentActionsInFlight.contains(.session(control.sessionID, .translation))) {
            context.send(viewAction: .disableAgentTranslation(sessionID: control.sessionID))
        }
    }

    /// Question 404: the avatar of the assistant that records, on the covered «Записує».
    private var coverBadge: NativeCallSheetAvatar? {
        guard let cover = context.viewState.recordingCover, cover.phase == .recording, let agent = cover.agentMxid else { return nil }
        return NativeCallSheetAvatar(mxid: agent,
                                     name: context.viewState.memberProfiles[agent]?.displayName ?? NativeCallFallbackName.make(mxid: agent),
                                     url: context.viewState.memberProfiles[agent]?.avatarURL,
                                     size: 22,
                                     mediaProvider: context.mediaProvider)
    }

    /// «Записувати дзвінок?», question 404's card or «nothing to translate» stands in for the buttons and the rows under
    /// them.
    private var isCardInPlace: Bool {
        switch context.assistantConfirmation {
        case .recording, .recordingCovered, .nothingToTranslate: true
        case .removeFromChat, nil: false
        }
    }

    /// The card a confirmation puts in the buttons' place: question 404's while someone else's recording covers the
    /// call, «nothing to translate» while everyone else speaks the language «Translate into» names.
    private func card(_ confirmation: NativeCallAssistantConfirmation?) -> NativeCallAssistantsCopy.Row? {
        switch confirmation {
        case .recordingCovered:
            NativeCallAssistantsCopy.recordingCoveredCard(context.viewState.recordingCover, context: context)
        case .nothingToTranslate:
            NativeCallAssistantsCopy.nothingToTranslateCard(context.viewState.translation, context: context)
        case .recording, .removeFromChat, nil:
            nil
        }
    }

    /// Question 404, layout C: a tap on the covered «Записує» puts whose recording it is in the buttons' place, with
    /// one way back; the sheet keeps its height (L8). Theirs stopping brings the buttons back too, with «Продовжити».
    /// «Nothing to translate» takes the same place, the same way (operator, 2026-11-15).
    private func noticeCard(_ card: NativeCallAssistantsCopy.Row) -> some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            NativeCallSheetNotice(systemImage: card.symbol, title: card.title, detail: card.detail, isCritical: false, isIconCritical: card.isCritical)
            NativeCallSheetPrimaryButton(title: UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredGotIt) {
                context.assistantConfirmation = nil
            }
        }
        .transition(.opacity)
    }

    /// L5 1.5: «Записывать звонок?» in the sheet, not a system alert.
    private var recordingConfirmation: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            recordingConfirmationContent
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var recordingConfirmationContent: some View {
        NativeCallSheetNotice(systemImage: "record.circle",
                              title: UntranslatedL10n.screenNativeCallAssistantsRecordConfirmTitle,
                              detail: NativeCallAssistantsCopy.recordingConfirmationDetail(context.viewState.recordingCover, context: context),
                              isCritical: false)
        NativeCallSheetPrimaryButton(title: UntranslatedL10n.screenNativeCallAssistantsRecordConfirmAction) {
            context.assistantConfirmation = nil
            context.send(viewAction: .toggleAssistantJob(.recording))
        }
        NativeCallSheetSecondaryButton(title: L10n.actionCancel) {
            context.assistantConfirmation = nil
        }
    }

    /// L4.2, L4.3: the language, then one main action — start your own, or, when someone already translates into it,
    /// listen to theirs, free — and one line on what it costs.
    @ViewBuilder
    private var newTranslation: some View {
        let translation = context.viewState.translation
        let language = translation.myLanguage
        translationRow
        if translation.production == nil, let option = translation.options.first(where: { $0.language == language && !$0.producers.isEmpty }) {
            NativeCallSheetPrimaryButton(title: UntranslatedL10n.screenNativeCallAssistantsListenLanguage(NativeCallTranslationCopy.languageName(language))) {
                context.send(viewAction: .setListeningChoice(.language(language)))
                context.send(viewAction: .dismissAgentCenter)
            }
            NativeCallSheetCaption(text: option.producerOwners.first.map { UntranslatedL10n.screenNativeCallAssistantsListenFreeBy(NativeCallTranslationCopy.firstName($0, context: context)) }
                ?? UntranslatedL10n.screenNativeCallAssistantsListenFree)
        } else if translation.production == nil {
            // Everyone here already speaks it: nothing to start.
            NativeCallSheetCaption(text: UntranslatedL10n.screenNativeCallAssistantsNothingToTranslate)
        } else {
            let isWaiting = panel.candidates.contains { context.viewState.agentActionsInFlight.contains(.add(agentID: $0.id)) }
                || ownAgent?.control.map { context.viewState.agentActionsInFlight.contains(.session($0.sessionID, .translation)) } == true
            NativeCallSheetPrimaryButton(title: UntranslatedL10n.screenNativeCallAssistantsStartTranslation, isWaiting: isWaiting) {
                context.send(viewAction: .produceTranslation)
            }
            if case .others(_, let speakers) = translation.production {
                NativeCallSheetCaption(text: UntranslatedL10n.screenNativeCallAssistantsNewTranslationOthers(speakers.map { NativeCallTranslationCopy.firstName($0, context: context) }
                        .formatted(.list(type: .and))))
            } else {
                NativeCallSheetCaption(text: UntranslatedL10n.screenNativeCallAssistantsStartTranslationDetail)
            }
        }
    }

    /// L5 4.1: everyone else's assistants, one row at the bottom with their stacked avatars.
    @ViewBuilder
    private var othersRow: some View {
        let foreign = agents.foreignAgents
        if !foreign.isEmpty, !context.viewState.isAssistantPage {
            NativeCallSheetRow(title: UntranslatedL10n.screenNativeCallAssistantsInCallMore(foreign.count),
                               showsChevron: true,
                               action: { path.append(.inTheCall) },
                               leading: { NativeCallSheetRowIcon(systemName: "person.2") },
                               trailing: { stackedAvatars(foreign) })
        }
    }

    private func stackedAvatars(_ foreign: [NativeCallAgentPresentation.Agent]) -> some View {
        HStack(spacing: -10) {
            ForEach(foreign.prefix(3)) { agent in
                NativeCallSheetAvatar(mxid: agent.mxid,
                                      name: agent.displayName,
                                      url: context.viewState.memberProfiles[agent.mxid]?.avatarURL,
                                      size: 24,
                                      mediaProvider: context.mediaProvider)
            }
        }
    }

    // MARK: Helpers

    private var removeConfirmationMessage: String? {
        guard let agent = ownAgent else { return nil }
        return NativeCallAssistantsCopy.removeConfirmation(isRecording: agent.shown.isRecording, isTakingNotes: agent.shown.isSummaryArmed)
    }

    private func isInFlight(_ row: NativeAgentCenterErrorScope.Row) -> Bool {
        guard let control = ownAgent?.control else { return false }
        return context.viewState.agentActionsInFlight.contains(.session(control.sessionID, row))
    }
}

// MARK: - Which assistant (3.3)

/// Scenario 9.3 — several own assistants: which one comes, remembered for this chat. Each says, in place, why it
/// can't come.
struct NativeCallAssistantChooserPage: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let job: NativeCallAssistantJob
    let onBack: () -> Void

    var body: some View {
        let panel = context.viewState.agents.panel
        NativeCallSheetPage {
            NativeCallSheetHeader(title: UntranslatedL10n.screenNativeCallAssistantsWhich,
                                  status: UntranslatedL10n.screenNativeCallAssistantsPickFooter,
                                  onBack: onBack,
                                  onClose: { context.send(viewAction: .dismissAgentCenter) },
                                  leading: { EmptyView() })
        } content: {
            ForEach(panel.candidates) { candidate in
                NativeCallSheetRow(title: candidate.displayName,
                                   detail: panel.startFailure(for: candidate).map { NativeCallAssistantsCopy.joinFailure($0, context: context).title },
                                   isSelected: candidate.id == context.viewState.pickedAssistantID,
                                   isWaiting: context.viewState.agentActionsInFlight.contains(.add(agentID: candidate.id)),
                                   action: { context.send(viewAction: .pickAssistant(agentID: candidate.id, job: job)) },
                                   leading: {
                                       NativeCallSheetAvatar(mxid: candidate.mxid, name: candidate.displayName, url: candidate.avatarURL,
                                                             size: 28, mediaProvider: context.mediaProvider)
                                   })
            }
        }
    }
}

// MARK: - A language (2.3, 5.1)

/// One language, picked on the sheet's glass: those someone already translates into first (free, with whose they are),
/// then all, the chosen one ticked and the phone's marked. A search under the header (L10) narrows every section by
/// the same rule as the chat tool's list; the field is there from the first frame, placeholders or not.
struct NativeCallLanguagePage: View {
    let title: String
    let status: String?
    /// Languages with a translation already, and the first name of whose assistant makes it.
    let free: [(language: String, owner: String?)]
    let languages: [String]
    /// The languages this person uses (`SuggestedLanguages`), between the free ones and all of them; none, no section.
    var suggested: [String] = []
    let selected: String?
    let phoneLanguage: String?
    /// The platform hasn't answered yet: which languages are already translated isn't known (loading rule).
    var isLoading = false
    let onBack: () -> Void
    let onClose: () -> Void
    let onPick: (String) -> Void

    @State private var query = ""

    /// The catalog's languages: `first` in that order, then the rest alphabetically, without `excluding`.
    /// The pocket interpreter's one pick (L11): the neighbour's language, the last one first; never your own, since
    /// translating into the language you already speak makes no sense.
    static func neighbourLanguages(catalog: [VoiceControlsCatalogLanguage], neighbour: String?, myLanguage: String) -> [String] {
        languages(catalog: catalog, first: [neighbour].compactMap(\.self), excluding: [myLanguage])
    }

    /// The suggested section's languages (every list's rule): the selected one, the phone's and the keyboards', as the
    /// catalog has them, without `excluding` — the free ones, or my own for the neighbour.
    static func suggested(selected: String?,
                          catalog: [VoiceControlsCatalogLanguage],
                          excluding: [String] = [],
                          preferred: [String],
                          keyboards: [String]) -> [String] {
        SuggestedLanguages.codes(selected: selected,
                                 preferred: preferred,
                                 keyboards: keyboards,
                                 catalog: catalog.map(\.code).filter { !excluding.contains($0) },
                                 limit: 5)
    }

    static func languages(catalog: [VoiceControlsCatalogLanguage], first: [String], excluding: [String] = []) -> [String] {
        var codes = catalog.map(\.code)
        // The catalog is every list's only source: a first entry it lacks isn't offered.
        let first = first.filter(codes.contains)
        codes = codes.filter { !first.contains($0) }
            .sorted { NativeCallTranslationCopy.languageTitle($0).localizedStandardCompare(NativeCallTranslationCopy.languageTitle($1)) == .orderedAscending }
        var ordered: [String] = []
        for code in first + codes where !ordered.contains(code) && !excluding.contains(code) {
            ordered.append(code)
        }
        return ordered
    }

    var body: some View {
        let shownFree = free.filter { NativeCallTranslationCopy.language($0.language, matches: query) }
        // A search shows one list, as the shared picker does.
        let shownSuggested = query.isEmpty ? suggested : []
        let shownLanguages = NativeCallTranslationCopy.languages(languages, matching: query).filter { !shownSuggested.contains($0) }
        NativeCallSheetPage {
            VStack(spacing: CompoundDesignTokens.space3X) {
                NativeCallSheetHeader(title: title, status: status, onBack: onBack, onClose: onClose) { EmptyView() }
                NativeCallSheetSearchField(text: $query, prompt: UntranslatedL10n.screenNativeCallAssistantsSearchLanguages)
            }
        } content: {
            if isLoading {
                NativeCallSheetSectionTitle(text: UntranslatedL10n.screenNativeCallAssistantsFreeSection)
                    .spiralLoadingSlot(true, label: L10n.commonLoading)
                ForEach(0..<4, id: \.self) { _ in
                    NativeCallSheetPlaceholderRow()
                }
            } else if !shownFree.isEmpty {
                NativeCallSheetSectionTitle(text: UntranslatedL10n.screenNativeCallAssistantsFreeSection)
                ForEach(shownFree, id: \.language) { item in
                    NativeCallSheetRow(icon: nil,
                                       title: NativeCallTranslationCopy.languageTitle(item.language),
                                       value: item.owner,
                                       isSelected: item.language == selected) { onPick(item.language) }
                }
            } else if shownLanguages.isEmpty, shownSuggested.isEmpty {
                NativeCallSheetCaption(text: UntranslatedL10n.screenLanguagePickerEmpty)
                    .padding(.top, CompoundDesignTokens.space4X)
            }
            if !isLoading, !shownSuggested.isEmpty {
                NativeCallSheetSectionTitle(text: UntranslatedL10n.screenLanguagePickerSuggestedSection)
                ForEach(shownSuggested, id: \.self, content: languageRow)
            }
            if !isLoading, !shownLanguages.isEmpty, !shownFree.isEmpty || !shownSuggested.isEmpty {
                NativeCallSheetSectionTitle(text: UntranslatedL10n.screenNativeCallAssistantsAllLanguages)
            }
            ForEach(isLoading ? [] : shownLanguages, id: \.self, content: languageRow)
        }
        // The list scrolls under the keyboard; a scroll puts the keyboard away (L10).
        .scrollDismissesKeyboard(.immediately)
    }

    private func languageRow(_ code: String) -> some View {
        NativeCallSheetRow(icon: nil,
                           title: NativeCallTranslationCopy.languageTitle(code),
                           detail: code == phoneLanguage ? UntranslatedL10n.screenNativeCallAssistantsPhoneLanguage : nil,
                           isSelected: code == selected) { onPick(code) }
    }
}

// MARK: - Other people's assistants (4.2, 4.3, 4.4)

/// L5 4.2: one glass row per assistant — whose, and what it does, from your side ("вас" when it concerns you).
struct NativeCallInTheCallPage: View {
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let onBack: () -> Void
    let onOpen: (String) -> Void

    /// What each does for you reads the platform's answer (who listens to what): placeholders until it comes.
    private var isLoading: Bool {
        NativeCallAssistantsLayout(panel: context.viewState.agents.panel).content == .placeholders
    }

    var body: some View {
        let foreign = context.viewState.agents.foreignAgents
        NativeCallSheetPage {
            NativeCallSheetHeader(title: UntranslatedL10n.screenNativeCallAssistantsInCall,
                                  status: UntranslatedL10n.screenNativeCallAssistantsCount(foreign.count),
                                  onBack: onBack,
                                  onClose: { context.send(viewAction: .dismissAgentCenter) },
                                  leading: { EmptyView() })
        } content: {
            ForEach(foreign) { agent in
                NativeCallSheetRow(title: NativeCallAssistantsCopy.foreignRowTitle(agent, context: context),
                                   detail: NativeCallAssistantsCopy.foreignStatus(agent, context: context),
                                   showsChevron: true,
                                   action: { onOpen(agent.mxid) },
                                   leading: {
                                       NativeCallSheetAvatar(mxid: agent.mxid,
                                                             name: agent.displayName,
                                                             url: context.viewState.memberProfiles[agent.mxid]?.avatarURL,
                                                             mediaProvider: context.mediaProvider)
                                   })
                                   .spiralLoadingSlot(isLoading, label: L10n.commonLoading)
                NativeCallInlineError(scope: .foreign(agent.mxid), context: context)
            }
            NativeCallSheetCaption(text: UntranslatedL10n.screenNativeCallAssistantsOthersFooter)
        }
        .animation(NativeCallAssistantsMotion.change, value: foreign)
        .onChange(of: foreign.isEmpty) { _, isEmpty in
            if isEmpty { onBack() }
        }
    }
}

/// L5 4.3: someone else's assistant, read-only — the same four buttons (on blue, off faded, none tappable) and what
/// they mean for you; a moderator may remove it from the chat, asked in place (4.4, D6).
struct NativeCallForeignAgentPage: View {
    let agent: NativeCallAgentPresentation.Agent
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let onBack: () -> Void

    /// The live agent, so the page follows the document while open and closes when the agent leaves.
    private var current: NativeCallAgentPresentation.Agent? {
        context.viewState.agents.agents.first { $0.mxid == agent.mxid }
    }

    private var isConfirmingRemoval: Bool {
        context.assistantConfirmation == .removeFromChat(agentMxid: agent.mxid)
    }

    var body: some View {
        let agent = current ?? agent
        let name = NativeCallAssistantsCopy.foreignName(agent, context: context)
        NativeCallSheetPage {
            NativeCallSheetHeader(title: name.title,
                                  status: name.subtitle,
                                  onBack: onBack,
                                  onClose: { context.send(viewAction: .dismissAgentCenter) },
                                  leading: {
                                      NativeCallSheetAvatar(mxid: agent.mxid,
                                                            name: agent.displayName,
                                                            url: context.viewState.memberProfiles[agent.mxid]?.avatarURL,
                                                            mediaProvider: context.mediaProvider)
                                  })
        } content: {
            // L8 A (4.4): while the removal is asked, its question takes the place of the buttons and the rows, in the
            // same frame; the header stays.
            if isConfirmingRemoval, context.viewState.agents.panel.canRemoveOthersFromChat {
                VStack(spacing: CompoundDesignTokens.space3X) {
                    removal(name: name.title)
                }
                .transition(.opacity)
            } else {
                VStack(spacing: CompoundDesignTokens.space3X) {
                    details(agent, name: name.title)
                }
                .transition(.opacity)
            }
        }
        .animation(NativeCallAssistantsMotion.change, value: agent)
        .animation(NativeCallAssistantsMotion.change, value: isConfirmingRemoval)
        .onChange(of: current == nil) { _, gone in
            if gone { onBack() }
        }
    }

    @ViewBuilder
    private func details(_ agent: NativeCallAgentPresentation.Agent, name: String) -> some View {
        NativeCallAssistantDockView(state: NativeCallAssistantDockState(.init(isTranslating: agent.shown.isTranslating && !agent.shown.isStandby,
                                                                              isTakingNotes: agent.shown.isSummaryArmed,
                                                                              isRecording: agent.shown.isRecording,
                                                                              isTalking: agent.shown.isConversationActive,
                                                                              isReadOnly: true)),
                                    isInteractive: false) { _ in }
        let isLoading = NativeCallAssistantsLayout(panel: context.viewState.agents.panel).content == .placeholders
        ForEach(NativeCallAssistantsCopy.foreignRows(agent, context: context)) { row in
            NativeCallSheetRow(title: row.title, detail: row.detail) {
                Image(systemName: row.symbol)
                    .font(.compound.bodyLG)
                    .foregroundStyle(row.isCritical ? Color.compound.iconCriticalPrimary : .compound.iconPrimary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            .spiralLoadingSlot(isLoading, label: L10n.commonLoading)
        }
        if context.viewState.agents.panel.canRemoveOthersFromChat {
            removal(name: name)
        }
    }

    @ViewBuilder
    private func removal(name: String) -> some View {
        let isWaiting = context.viewState.agentActionsInFlight.contains(.removeFromChat(agentMxid: agent.mxid))
        if isConfirmingRemoval {
            NativeCallSheetNotice(systemImage: "person.badge.minus",
                                  title: UntranslatedL10n.screenNativeCallAssistantsRemoveFromChatTitle(name),
                                  detail: UntranslatedL10n.screenNativeCallAssistantsRemoveFromChatMessage(name),
                                  isCritical: false)
            NativeCallSheetPrimaryButton(title: UntranslatedL10n.screenNativeCallAssistantsRemove, isDestructive: true, isWaiting: isWaiting) {
                context.send(viewAction: .removeAgentFromChat(agentMxid: agent.mxid))
            }
            NativeCallSheetSecondaryButton(title: L10n.actionCancel) {
                context.assistantConfirmation = nil
            }
        } else {
            NativeCallSheetRow(icon: "person.badge.minus",
                               title: UntranslatedL10n.screenNativeCallAssistantsRemoveFromChat,
                               role: .destructive,
                               isWaiting: isWaiting) {
                context.assistantConfirmation = .removeFromChat(agentMxid: agent.mxid)
            }
        }
        NativeCallInlineError(scope: .foreign(agent.mxid), context: context)
    }
}

// MARK: - Shared

/// A failed write, by what it concerns (audit F8): removing an assistant, or someone else's from the chat.
struct NativeCallInlineError: View {
    let scope: NativeAgentCenterErrorScope?
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        let panel = context.viewState.agents.panel
        if let scope, panel.lastErrorScope == scope, let error = panel.lastError {
            NativeCallSheetNotice(systemImage: "exclamationmark.circle",
                                  title: NativeCallAssistantsCopy.errorTitle(error, context: context),
                                  detail: nil)
        }
    }
}

// MARK: - Copy

/// Every word the sheet says about an assistant, in one place.
enum NativeCallAssistantsCopy {
    struct Row: Identifiable {
        var id: String {
            title
        }

        let title: String
        let detail: String?
        /// An SF Symbol.
        let symbol: String
        /// Red, like the call's ЗАПИСЬ: recording, a problem.
        var isCritical = false
    }

    /// F6 — where an artifact went, as the backend says (`recording.delivery`).
    static func isDelivering(_ artifact: NativeAgentCenterArtifact) -> Bool {
        switch artifact.delivery {
        case .delivered, .failed: true
        case .pending: artifact.isStopped
        case .notArmed: false
        }
    }

    /// A stopped recording: Delivering… / Delivered to this chat / … to your chat with your assistant / failed.
    static func recordingDelivery(_ artifact: NativeAgentCenterArtifact) -> String? {
        switch artifact.delivery {
        case .pending: UntranslatedL10n.screenNativeCallAssistantsDeliveryPending
        case .notArmed: nil
        case .delivered, .failed: notesDelivery(artifact)
        }
    }

    /// Notes are made when the call ends, so "pending" during the call is not news; only the outcome is.
    static func notesDelivery(_ artifact: NativeAgentCenterArtifact) -> String? {
        switch artifact.delivery {
        case .delivered(let target):
            target == "owner_dm"
                ? UntranslatedL10n.screenNativeCallAssistantsDeliveredOwnerDm
                : UntranslatedL10n.screenNativeCallAssistantsDeliveredRoom
        case .failed: UntranslatedL10n.screenNativeCallAssistantsDeliveryFailed
        case .pending, .notArmed: nil
        }
    }

    /// The translation's own line when the document can't say it (rows 10, 11): starting, from the owner's REST
    /// `syncing` while the document still shows the old mode; else standing by — «nothing to translate» when everyone
    /// else speaks its language, «takes over» only when another assistant covers them. Nil: the document says it.
    static func translationStatus(isSyncing: Bool, isStandby: Bool, isNothingToTranslate: Bool = false) -> String? {
        if isSyncing { return UntranslatedL10n.screenNativeCallAssistantsStatusStarting }
        if isStandby {
            return isNothingToTranslate ? UntranslatedL10n.screenNativeCallAssistantsStatusNothingToTranslate : UntranslatedL10n.screenNativeCallAssistantsStatusStandby
        }
        return nil
    }

    /// What an own assistant does, in the header's one line (L5): the main thing only — «Переводит на украинский»,
    /// «Разговаривает с вами», «Ведёт заметки»; the buttons under it say the rest.
    static func status(_ shown: NativeCallAgentPresentation.Shown, catalog: [VoiceControlsCatalogLanguage]) -> String {
        if shown.isTranslating {
            return UntranslatedL10n.screenNativeCallAssistantsTranslating(NativeCallAgentStatusCopy.languageList(shown.languages, catalog: catalog))
        }
        if shown.isConversationActive {
            return UntranslatedL10n.screenNativeCallAssistantsJobTalks
        }
        return shown.isSummaryArmed ? UntranslatedL10n.screenNativeCallAgentPillTakingNotes : UntranslatedL10n.screenNativeCallAgentPillListening
    }

    static func title(_ job: NativeCallAssistantJob) -> String {
        switch job {
        case .translation: UntranslatedL10n.screenNativeCallAssistantsJobTranslation
        case .summary: UntranslatedL10n.screenNativeCallAssistantsJobSummary
        case .recording: UntranslatedL10n.screenNativeCallAssistantsRecording
        case .conversation: UntranslatedL10n.screenNativeCallAssistantsJobConversation
        }
    }

    /// The dock's word for a button: «Записує» while someone else's recording covers the call, «Продовжити» once it
    /// stopped (question 404); the job's name otherwise.
    static func title(_ button: NativeCallAssistantDockState.Button) -> String {
        switch button.cover {
        case .recording: UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredButton
        case .stopped: UntranslatedL10n.screenNativeCallAssistantsRecordingContinue
        case nil: title(button.job)
        }
    }

    /// Question 404, layout C: «Богдан уже записує цей дзвінок · Файл прийде в цей чат. Коли запис зупиниться, тут
    /// з’явиться «Продовжити».» — by the owner's first name, «Хтось» when unknown. The name is the sentence's subject,
    /// in the present tense, so no language declines it or agrees a verb with its gender (operator, 2026-11-12). Nil
    /// unless someone else's recording covers the call.
    static func recordingCoveredCard(_ cover: NativeCallRecordingCover?, context: NativeCallScreenViewModel.Context) -> Row? {
        guard let cover, cover.phase == .recording else { return nil }
        let owner = cover.ownerMxid.map { NativeCallTranslationCopy.firstName($0, context: context) }
        return Row(title: owner.map { UntranslatedL10n.screenNativeCallAssistantsRecordingCovered($0) } ?? UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredSomeone,
                   detail: UntranslatedL10n.screenNativeCallAssistantsRecordingCoveredCardDetail,
                   symbol: "record.circle", isCritical: true)
    }

    /// «Аліна вже говорить мовою перекладу: українська · Перекладати нічого…» — the one other person by first name, as
    /// the subject; «Усі…» for several. The language stands after a colon in the languages that decline it, so no
    /// locale agrees a case with the catalog's name (operator, 2026-11-15). Nil while there is something to translate.
    static func nothingToTranslateCard(_ translation: NativeCallTranslationState, context: NativeCallScreenViewModel.Context) -> Row? {
        let language = translation.myLanguage
        guard translation.isNothingToTranslate(into: language) else { return nil }
        let name = NativeCallTranslationCopy.languageName(language)
        let title = if translation.speakers.count == 1, let person = translation.speakers.first {
            UntranslatedL10n.screenNativeCallAssistantsNothingToTranslateOne(NativeCallTranslationCopy.firstName(person, context: context), name)
        } else {
            UntranslatedL10n.screenNativeCallAssistantsNothingToTranslateEveryone(name)
        }
        return Row(title: title, detail: UntranslatedL10n.screenNativeCallAssistantsNothingToTranslateDetail, symbol: "translate")
    }

    /// «Записувати дзвінок?»'s line (L5 1.5). After someone else's recording stopped — the button said «Продовжити» —
    /// it says so, and that yours is a file of its own (question 404).
    static func recordingConfirmationDetail(_ cover: NativeCallRecordingCover?, context: NativeCallScreenViewModel.Context) -> String {
        guard let cover, cover.phase == .stopped else { return UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessage }
        return cover.ownerMxid.map { UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterOther(NativeCallTranslationCopy.firstName($0, context: context)) }
            ?? UntranslatedL10n.screenNativeCallAssistantsRecordConfirmMessageAfterSomeone
    }

    static func symbol(_ job: NativeCallAssistantJob) -> String {
        switch job {
        case .translation: "translate"
        case .summary: "square.and.pencil"
        case .recording: "record.circle"
        case .conversation: "waveform"
        }
    }

    /// Why an own assistant can't come, and what that means (F3).
    static func joinFailure(_ reason: NativeAgentCenterJoinFailure, context: NativeCallScreenViewModel.Context) -> Row {
        switch reason {
        case .paused:
            .init(title: UntranslatedL10n.screenNativeCallAssistantsReasonPaused,
                  detail: UntranslatedL10n.screenNativeCallAssistantsReasonPausedDetail, symbol: "pause.fill")
        case .aiConsentOwner:
            .init(title: UntranslatedL10n.screenNativeCallTranslateBlockConsentOwner,
                  detail: UntranslatedL10n.screenNativeCallAssistantsReasonConsentOwnerDetail, symbol: "exclamationmark.circle")
        case .aiConsentRoom:
            .init(title: UntranslatedL10n.screenNativeCallAssistantsReasonConsentRoom,
                  detail: UntranslatedL10n.screenNativeCallAssistantsReasonConsentRoomDetail, symbol: "person.2")
        case .askToJoin:
            .init(title: UntranslatedL10n.screenNativeCallAssistantsReasonAskToJoin,
                  detail: UntranslatedL10n.screenNativeCallAssistantsReasonAskToJoinDetail, symbol: "lock")
        case .budgetReached:
            .init(title: UntranslatedL10n.screenNativeCallAssistantsReasonBudget,
                  detail: UntranslatedL10n.screenNativeCallAssistantsReasonBudgetDetail, symbol: "hourglass")
        // The Limit page's wording, after the category's name: «Звонки на паузе до понедельника, 3:00».
        case .categoryPaused(let category, let pause):
            .init(title: AgentLimitWording.categoryPauseLine(category, pause),
                  detail: pause == nil ? UntranslatedL10n.screenNativeCallAssistantsReasonCategoryPausedDetail : nil, symbol: "pause.fill")
        case .cannotJoinCalls:
            .init(title: UntranslatedL10n.screenNativeCallAssistantsReasonCannotJoinCalls,
                  detail: UntranslatedL10n.screenNativeCallAssistantsReasonCannotJoinCallsDetail, symbol: "mic.slash")
        case .failed:
            .init(title: UntranslatedL10n.screenNativeCallAssistantsReasonFailed,
                  detail: UntranslatedL10n.screenNativeCallAssistantsReasonFailedDetail, symbol: "exclamationmark.triangle")
        case .needsUpdate:
            .init(title: UntranslatedL10n.screenNativeCallAssistantsReasonNeedsUpdate, detail: nil, symbol: "exclamationmark.triangle")
        }
    }

    /// Critique item 5 — someone else's assistant in the viewer's language: «Ассистент Mira» and «Владелец: Mira
    /// Testova» for a personal one, its own name and its owner otherwise.
    static func foreignName(_ agent: NativeCallAgentPresentation.Agent, context: NativeCallScreenViewModel.Context) -> (title: String, subtitle: String?) {
        switch NativeCallForeignAssistantName(agentMxid: agent.mxid, displayName: agent.displayName, people: people(context)) {
        case .personal(let owner):
            (UntranslatedL10n.screenNativeCallAssistantsOwnerAssistant(firstName(owner)), UntranslatedL10n.screenNativeCallAssistantsOwner(owner))
        case .custom(let name, let owner):
            (name, owner.map { UntranslatedL10n.screenNativeCallAssistantsOwner($0) })
        }
    }

    /// «Ассистент Mira» for a personal one, by its owner's first name; its own name otherwise.
    static func foreignRowTitle(_ agent: NativeCallAgentPresentation.Agent, context: NativeCallScreenViewModel.Context) -> String {
        foreignName(agent, context: context).title
    }

    private static func people(_ context: NativeCallScreenViewModel.Context) -> [String: String] {
        Dictionary(context.viewState.humanParticipants.map { ($0.userID, context.viewState.memberProfiles[$0.userID]?.displayName ?? NativeCallFallbackName.make(mxid: $0.userID)) }) { first, _ in first }
    }

    private static func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// L5 4.2: everything someone else's assistant does, in one sentence from your side.
    static func foreignStatus(_ agent: NativeCallAgentPresentation.Agent, context: NativeCallScreenViewModel.Context) -> String {
        let catalog = context.viewState.agents.panel.catalog
        let translatesYou: [String]? = switch agent.live.coversMe {
        case .live(let languages), .interpreter(let languages): languages
        case nil: nil
        }
        if agent.live.stoppedReason == .ownerLeft {
            return UntranslatedL10n.screenNativeCallAssistantsStatusOwnerLeft
        }
        let languages = NativeCallAgentStatusCopy.languageList(agent.shown.languages, catalog: catalog)
        let status = foreignStatus(translatesYou: translatesYou.map { NativeCallAgentStatusCopy.languageList($0, catalog: catalog) },
                                   translates: agent.shown.isTranslating && !agent.shown.isStandby ? languages : nil,
                                   standsBy: agent.shown.isStandby ? languages : nil,
                                   talks: agent.shown.isConversationActive,
                                   records: agent.shown.isRecording,
                                   takesNotes: agent.shown.isSummaryArmed)
        return isHeard(agent, context: context) ? "\(status) · \(UntranslatedL10n.screenNativeCallAssistantsForeignYouListen)" : status
    }

    /// You listen to its translation now.
    static func isHeard(_ agent: NativeCallAgentPresentation.Agent, context: NativeCallScreenViewModel.Context) -> Bool {
        let translation = context.viewState.translation
        return translation.options.contains { $0.language == translation.listeningLanguage && $0.producers.contains(agent.mxid) }
    }

    /// The main thing first — it translates you, translates, stands by («В резерве · английский», D10), or talks —
    /// then " · records", " · takes notes". `translatesYou`, `translates` and `standsBy` are the languages, already
    /// worded.
    static func foreignStatus(translatesYou: String?, translates: String?, standsBy: String? = nil, talks: Bool, records: Bool, takesNotes: Bool) -> String {
        let main: String? = if let translatesYou {
            UntranslatedL10n.screenNativeCallAssistantsForeignStatusTranslatesYou(translatesYou)
        } else if let translates {
            UntranslatedL10n.screenNativeCallAssistantsForeignTranslates(translates)
        } else if let standsBy {
            UntranslatedL10n.screenNativeCallAssistantsForeignStandby(standsBy)
        } else if talks {
            UntranslatedL10n.screenNativeCallAssistantsForeignTalks
        } else {
            nil
        }
        guard let main else {
            if records {
                return [UntranslatedL10n.screenNativeCallAssistantsForeignStatusRecordsYou,
                        takesNotes ? UntranslatedL10n.screenNativeCallAssistantsForeignStatusAlsoNotes : nil]
                    .compactMap(\.self).joined(separator: " · ")
            }
            return takesNotes ? UntranslatedL10n.screenNativeCallAssistantsForeignNotes : UntranslatedL10n.screenNativeCallAssistantsForeignListening
        }
        return [main,
                records ? UntranslatedL10n.screenNativeCallAssistantsForeignStatusAlsoRecords : nil,
                takesNotes ? UntranslatedL10n.screenNativeCallAssistantsForeignStatusAlsoNotes : nil]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// L5 4.3: what someone else's assistant does, from your side (D10), and what each means for you.
    static func foreignRows(_ agent: NativeCallAgentPresentation.Agent, context: NativeCallScreenViewModel.Context) -> [Row] {
        let catalog = context.viewState.agents.panel.catalog
        var rows: [Row] = []
        let languages: [String]? = switch agent.live.coversMe {
        case .live(let languages), .interpreter(let languages): languages
        case nil: agent.shown.isTranslating && !agent.shown.isStandby ? agent.shown.languages : nil
        }
        if agent.live.coversMe == nil, agent.shown.isStandby {
            // D10: on, holding no lane — it takes over if the language's producer stops; it translates nothing yet.
            rows.append(Row(title: UntranslatedL10n.screenNativeCallAssistantsForeignStandby(NativeCallAgentStatusCopy.languageList(agent.shown.languages, catalog: catalog)),
                            detail: nil,
                            symbol: "translate"))
        }
        if let languages {
            let list = NativeCallAgentStatusCopy.languageList(languages, catalog: catalog)
            let title = agent.live.coversMe == nil
                ? UntranslatedL10n.screenNativeCallAssistantsForeignTranslates(list)
                : UntranslatedL10n.screenNativeCallAssistantsForeignTranslatesYou(list)
            let detail = [UntranslatedL10n.screenNativeCallAssistantsForeignForLanguage(list),
                          isHeard(agent, context: context) ? UntranslatedL10n.screenNativeCallAssistantsForeignYouListen : nil]
                .compactMap(\.self).joined(separator: " · ")
            rows.append(Row(title: title, detail: detail, symbol: "translate"))
        }
        if agent.shown.isRecording {
            rows.append(Row(title: UntranslatedL10n.screenNativeCallAssistantsForeignRecordsYou,
                            detail: UntranslatedL10n.screenNativeCallAssistantsForeignRecordsYouDetail,
                            symbol: "record.circle",
                            isCritical: true))
        }
        if agent.shown.isSummaryArmed {
            rows.append(Row(title: UntranslatedL10n.screenNativeCallAssistantsForeignNotes,
                            detail: UntranslatedL10n.screenNativeCallAssistantsForeignNotesDetail,
                            symbol: "square.and.pencil"))
        }
        if agent.shown.isConversationActive {
            rows.append(Row(title: UntranslatedL10n.screenNativeCallAssistantsForeignTalks,
                            detail: UntranslatedL10n.screenNativeCallAssistantsForeignTalksDetail,
                            symbol: "waveform"))
        }
        if rows.isEmpty {
            rows.append(Row(title: UntranslatedL10n.screenNativeCallAssistantsForeignListening,
                            detail: UntranslatedL10n.screenNativeCallAssistantsForeignListeningDetail,
                            symbol: "ear"))
        }
        return rows
    }

    static func errorTitle(_ error: NativeAgentCenterError, context: NativeCallScreenViewModel.Context) -> String {
        switch error {
        case .conflict: UntranslatedL10n.screenNativeCallAssistantsErrorChanged
        case .gone: UntranslatedL10n.screenNativeCallAssistantsErrorLeft
        case .conversationRefused: UntranslatedL10n.screenNativeCallAssistantsErrorTalkRefused
        // Row 12: the limit's or the pause's own line.
        case .translationPaused: error.localizedDescription
        case .rejected, .notOwner, .agentPaused, .unavailable: UntranslatedL10n.screenNativeCallAssistantsErrorFailed
        }
    }

    /// What a removal still posts; nil when nothing is recording or taking notes, and then no confirmation is asked.
    static func removeConfirmation(isRecording: Bool, isTakingNotes: Bool) -> String? {
        switch (isRecording, isTakingNotes) {
        case (true, true): UntranslatedL10n.screenNativeCallAssistantsRemoveConfirmMessage
        case (true, false): UntranslatedL10n.screenNativeCallAssistantsRemoveConfirmRecording
        case (false, true): UntranslatedL10n.screenNativeCallAssistantsRemoveConfirmNotes
        case (false, false): nil
        }
    }
}

/// Which rows set the translation's languages in the own assistant's sheet (L11, S1).
enum NativeCallTranslationSettingRow: Equatable {
    /// «Перевод на · Украинский ›»: the language you hear, in a call between people.
    case translateInto
    /// The pocket interpreter's pair, in the private call: «Я говорю · Украинский ›» — "my language", the same page as
    /// «Перевод на» — over «Человек рядом · Французский ›».
    case pocketPair

    init(isPrivateCall: Bool) {
        self = isPrivateCall ? .pocketPair : .translateInto
    }

    /// How many rows it takes, for the placeholders that stand in for them.
    var rowCount: Int {
        switch self {
        case .translateInto: 1
        case .pocketPair: 2
        }
    }
}
