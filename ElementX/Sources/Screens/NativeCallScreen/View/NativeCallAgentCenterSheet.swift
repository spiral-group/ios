//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0063 Slice 3): the native Agent Center panel.
//
// Agent state is presented here, separately from the human participant tiles.
// Everything the sheet says about an agent comes from
// `NativeCallAgentPresentation` (`context.viewState.agents`) and is worded by
// `NativeCallAgentStatusCopy`; the sheet never reads the REST snapshot or the
// raw claims — the closeout audit's lint rule enforces it.

struct NativeCallAgentCenterSheet: View {
    // The sheet is its own presentation root: without `@ObservedObject` the
    // Combine context never invalidates it and every backend change renders
    // into a frozen snapshot.
    @ObservedObject var context: NativeCallScreenViewModel.Context

    /// The candidate whose add-flow is open. Drives a programmatic push so
    /// the row can stay a plain Compound navigation row (one chevron).
    @State private var addingCandidate: NativeAgentCenterCandidate?

    var body: some View {
        ElementNavigationStack {
            Form {
                if let error = context.viewState.agents.panel.lastError {
                    Section {
                        NativeCallErrorCard(error: error) {
                            context.send(viewAction: .reloadAgentCenter)
                        }
                    }
                }

                whatYouHear

                activeSessions

                otherAgents

                availableAgents
            }
            .compoundList()
            .navigationDestination(item: $addingCandidate) { candidate in
                NativeCallAddAgentScreen(context: context, candidate: candidate)
            }
            .navigationTitle(UntranslatedL10n.screenNativeCallAgentCenterTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // `10 · Agent Center`: Done sits on the trailing edge.
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) {
                        context.send(viewAction: .dismissAgentCenter)
                    }
                    .fontWeight(.semibold)
                }
            }
            .disabled(context.viewState.isAgentActionInFlight)
        }
    }

    /// The one control EVERY participant has, above the owner-only agent
    /// controls: hear the translation the call produces, or the original
    /// voices only. ONE switch, not a language radio — neither airing
    /// style leaves a per-listener language to pick (consecutive is
    /// communal by ADR-0075 D8, simultaneous is single-language by
    /// construction). The languages are NAMED here so the listener knows
    /// what the switch means. Client-only, never persisted (ADR-0075 D7).
    @ViewBuilder
    private var whatYouHear: some View {
        let listening = context.viewState.listening
        if !listening.producedLanguages.isEmpty {
            Section {
                ListRow(kind: .custom {
                    HStack(spacing: 12) {
                        NativeCallControlRowIcon(systemName: "ear")

                        NativeCallControlRowText(title: UntranslatedL10n.screenNativeCallListeningTranslation,
                                                 subtitle: NativeCallAgentStatusCopy.languageList(listening.producedLanguages))

                        Spacer()

                        Toggle("", isOn: Binding(get: { listening.channel == .everything },
                                                 set: { context.send(viewAction: .setListeningChoice($0 ? .translation : .original)) }))
                            .labelsHidden()
                            .accessibilityLabel(UntranslatedL10n.screenNativeCallListeningTranslation)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                })
            } header: {
                Text(UntranslatedL10n.screenNativeCallAgentCenterListeningSection)
            } footer: {
                // Brief 0066 rev. 2 — what "translation" does to the voices
                // under it, said once, while a Live agent is in the call.
                Text(listening.channel == .everything && hasLiveStyleAgent
                    ? "\(UntranslatedL10n.screenNativeCallAgentCenterListeningFooter) \(UntranslatedL10n.screenNativeCallListeningOriginalQuietFooter)"
                    : UntranslatedL10n.screenNativeCallAgentCenterListeningFooter)
            }
            .compoundListSectionHeader()
        }
    }

    /// A Live (simultaneous) agent's translation plays over quiet originals;
    /// Interpreter renderings are shared and never duck anyone.
    private var hasLiveStyleAgent: Bool {
        context.viewState.agents.agents.contains { $0.shown.style == .simultaneous }
    }

    /// True while the sheet has nothing loaded yet and the reload is still
    /// out. The empty-state copy is a STATEMENT ("no agents in this call"),
    /// and stating it before the first load returned was a lie on every
    /// slow network (audit A6-2) — loading gets a spinner, not a verdict.
    private var isFirstLoadStillOut: Bool {
        let agents = context.viewState.agents
        return agents.panel.isLoading
            && agents.agents.isEmpty
            && agents.joining.isEmpty
            && agents.removing.isEmpty
            && agents.panel.candidates.isEmpty
    }

    @ViewBuilder
    private var activeSessions: some View {
        if isFirstLoadStillOut {
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.commonLoading)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
            } header: {
                Text(UntranslatedL10n.screenNativeCallAgentCenterActiveSection)
            }
            .compoundListSectionHeader()
        } else if context.viewState.agents.agents.isEmpty, context.viewState.agents.joining.isEmpty, context.viewState.agents.removing.isEmpty {
            Section {
                Text(UntranslatedL10n.screenNativeCallAgentCenterEmpty)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            } header: {
                Text(UntranslatedL10n.screenNativeCallAgentCenterActiveSection)
            }
            .compoundListSectionHeader()
        } else {
            // `10 · Agent Center` draws each concern as its OWN card:
            // the head, then the controls, then the remove action.
            let own = context.viewState.agents.ownAgents
            ForEach(own) { agent in
                NativeCallAgentSessionSections(agent: agent,
                                               context: context,
                                               showsHeader: agent.id == own.first?.id)
            }
            // Attach accepted, agent not yet in the media roster: a card
            // that says so, never a "Ready" with controls that would 409.
            let absent = context.viewState.agents.joining + context.viewState.agents.removing
            ForEach(absent, id: \.sessionID) { control in
                NativeCallAgentJoiningSection(control: control,
                                              status: control.isEndRequested
                                                  ? UntranslatedL10n.screenNativeCallAgentCenterRemoving
                                                  : UntranslatedL10n.screenNativeCallAgentCenterJoining,
                                              context: context,
                                              showsHeader: own.isEmpty && control.sessionID == absent.first?.sessionID)
            }
        }
    }

    /// Phase 2 (G3) / Brief 0066 — every agent someone else brought, in
    /// the same voice as the owner's head: what it does (style · booths),
    /// the wave while it airs, and what that means for MY ears. Identity
    /// from the RTC roster, everything else from the `spiral.agent.state`
    /// document, so this list is identical on every device with no
    /// owner-gated REST behind it. Tap → the read-only detail card, so a
    /// multi-booth configuration is never truncated to one line.
    @ViewBuilder
    private var otherAgents: some View {
        let foreign = context.viewState.agents.foreignAgents
        if !foreign.isEmpty {
            Section {
                ForEach(foreign) { agent in
                    ListRow(kind: .custom {
                        NavigationLink {
                            NativeCallForeignAgentDetail(agent: agent, context: context)
                        } label: {
                            NativeCallForeignAgentRow(agent: agent, context: context)
                        }
                        .buttonStyle(.plain)
                    })
                }
            } header: {
                Text(UntranslatedL10n.screenNativeCallAgentCenterOthersSection)
            }
            .compoundListSectionHeader()
        }
    }

    @ViewBuilder
    private var availableAgents: some View {
        // An agent already in the call is not offered again (filtered in
        // the presentation's panel).
        let candidates = context.viewState.agents.panel.candidates

        Section {
            if isFirstLoadStillOut {
                // Same honesty rule as the sessions card (audit A6-2):
                // "no agents available" is a verdict the first load has
                // not returned yet.
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.commonLoading)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
            } else if candidates.isEmpty {
                Text(UntranslatedL10n.screenNativeCallAgentCenterNoAgents)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
            } else {
                // `11 · Add an agent`: each candidate opens the add flow —
                // the quick "Translate me" card plus the what-it-does
                // toggles, applied in ONE attach.
                ForEach(candidates) { candidate in
                    // The agent is a WHO, not a device: its own avatar and its
                    // own name, exactly as the card above renders it once it
                    // has joined. This row used to show a laptop glyph with
                    // the raw MXID underneath — a login presented as identity.
                    //
                    // Shape copied from the translation row below: the
                    // NavigationLink lives INSIDE the ListRow. Wrapping the
                    // ListRow in the link instead is what drew TWO chevrons.
                    // Compound's own avatar row, driven by a programmatic push:
                    // the app's `AgentRow` is built exactly this way. Wrapping
                    // a ListRow in a SwiftUI NavigationLink — what this row did
                    // before — draws the link's chevron AND the row's, which is
                    // why the picker shipped with two.
                    ListRow(label: .avatar(title: candidate.displayName,
                                           status: nil,
                                           description: nil,
                                           icon: LoadableAvatarImage(url: candidate.avatarURL,
                                                                     name: candidate.displayName,
                                                                     contentID: candidate.mxid,
                                                                     avatarSize: .custom(32),
                                                                     mediaProvider: context.mediaProvider),
                                           role: nil),
                            kind: .navigationLink { addingCandidate = candidate })
                }
            }
        } header: {
            Text(UntranslatedL10n.screenNativeCallAgentCenterAvailableSection)
        } footer: {
            // Brief 0067: the widget sheet's AI disclosure, kept on the
            // native surface that offers the functions.
            Text(UntranslatedL10n.screenNativeCallAgentCenterAiDisclosure)
                .compoundListSectionFooter()
        }
        .compoundListSectionHeader()
    }
}

/// `19 · Failure states`: the error card — a critical-tinted glyph, what
/// happened, why, and the one recovery that helps. The plain red line it
/// replaces said WHAT failed but never WHAT TO DO.
private struct NativeCallErrorCard: View {
    let error: NativeAgentCenterError
    let onReload: () -> Void

    var body: some View {
        ListRow(kind: .custom {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.compound.iconCriticalPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.compound.bgCriticalSubtle, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(body_)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                if hasReload {
                    Divider()

                    Button(action: onReload) {
                        Text(UntranslatedL10n.screenNativeCallErrorConflictAction)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.compound.textActionAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        })
    }

    private var title: String {
        switch error {
        case .conflict: UntranslatedL10n.screenNativeCallErrorConflictTitle
        case .gone: UntranslatedL10n.screenNativeCallErrorGoneTitle
        case .unavailable: UntranslatedL10n.screenNativeCallErrorUnavailableTitle
        case .rejected, .notOwner, .invalidBooths, .conversationRefused, .agentPaused: UntranslatedL10n.screenNativeCallErrorRejectedTitle
        }
    }

    private var body_: String {
        switch error {
        case .unavailable: UntranslatedL10n.screenNativeCallErrorUnavailableBody
        default: error.localizedDescription
        }
    }

    /// Reloading recovers a stale or ended snapshot; it cannot fix an
    /// unreachable platform or a policy refusal.
    private var hasReload: Bool {
        switch error {
        case .conflict, .gone: true
        case .unavailable, .rejected, .notOwner, .invalidBooths, .conversationRefused, .agentPaused: false
        }
    }
}

/// One attached agent, drawn exactly as `10 · Agent Center` cards it:
/// the head (who + what it does + the wave), the controls
/// (Translation / Recording / Summary as single rows with their control
/// on the trailing edge), and the remove action — three separate cards.
private struct NativeCallAgentSessionSections: View {
    let agent: NativeCallAgentPresentation.Agent
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let showsHeader: Bool

    private var isLeaving: Bool {
        agent.shown.presence == .leaving
    }

    /// The DELETE landed (control) or the agent is on its way out (shown):
    /// Remove goes inert — a second DELETE does no work — and the
    /// conversation switch goes, since a session tearing down cannot talk.
    private var isEnding: Bool {
        isLeaving || agent.control?.isEndRequested == true
    }

    var body: some View {
        headSection

        if let control = agent.control, control.canControl {
            // The design groups the agent's three cards tightly (8pt) —
            // one agent, one cluster; the default spacing reads as
            // unrelated sections.
            controlsSection(control)
                .listSectionSpacing(8)
                // A session on its way out cannot take a recording, summary
                // or translation write — the backend answers 409/410 — so
                // the controls stop inviting one.
                .disabled(isLeaving)
            removeSection(control)
                .listSectionSpacing(8)
        }
    }

    private var headSection: some View {
        Section {
            NativeCallAgentHeadRow(mxid: agent.mxid,
                                   name: agent.displayName,
                                   status: NativeCallAgentStatusCopy.headStatus(agent,
                                                                                ownUserID: context.viewState.ownUserID,
                                                                                profiles: context.viewState.memberProfiles,
                                                                                catalog: context.viewState.agents.panel.catalog),
                                   isAiring: agent.shown.isAiring,
                                   context: context)
        } header: {
            if showsHeader {
                Text(UntranslatedL10n.screenNativeCallAgentCenterActiveSection)
            }
        }
        .compoundListSectionHeader()
    }

    private func controlsSection(_ control: NativeCallAgentPresentation.Control) -> some View {
        Section {
            // Brief 0080 — the assistant talks or stays silent, both ways, in
            // any call. Not offered while the call interprets (the backend
            // refuses it then) or once the session is ending. The subtitle is
            // never truncated: "everyone hears it" is the point of the row.
            if control.conversation.isAvailable, !isEnding {
                ListRow(kind: .custom {
                    HStack(spacing: 12) {
                        NativeCallControlRowIcon(systemName: "bubble.left.and.bubble.right")

                        NativeCallControlRowText(title: UntranslatedL10n.screenNativeCallAgentCenterConversation,
                                                 subtitle: NativeCallAgentStatusCopy.conversationRow(agent),
                                                 subtitleLineLimit: nil)

                        Spacer()

                        Toggle("", isOn: conversationBinding(control))
                            .labelsHidden()
                            .accessibilityLabel(UntranslatedL10n.screenNativeCallAgentCenterConversation)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                })
            }

            // Brief 0062 parity: translation is a full two-tier booth
            // editor (who → languages, style, room defaults) on its own
            // screen — inline language toggles wrote a flat `anyone`
            // booth and silently erased per-speaker configuration. The
            // design's quick off lives on the trailing toggle; turning
            // ON needs a configuration, so the row navigates (the
            // Settings VPN pattern: text opens the editor, the switch
            // cuts the engine).
            if !context.viewState.agents.panel.catalog.isEmpty {
                ListRow(kind: .custom {
                    HStack(spacing: 12) {
                        NavigationLink {
                            NativeCallTranslationEditorScreen(context: context, sessionID: control.sessionID)
                        } label: {
                            HStack(spacing: 12) {
                                NativeCallControlRowIcon(systemName: "globe")

                                NativeCallControlRowText(title: UntranslatedL10n.screenNativeCallAgentCenterTranslation,
                                                         subtitle: NativeCallAgentStatusCopy.translationRow(agent,
                                                                                                            ownUserID: context.viewState.ownUserID,
                                                                                                            profiles: context.viewState.memberProfiles,
                                                                                                            catalog: context.viewState.agents.panel.catalog))

                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        // The switch shows the SHOWN truth — the same fact
                        // the capsule shows — so a runtime that refused
                        // the write cannot leave the switch lying on.
                        if agent.shown.isTranslating {
                            Toggle("", isOn: translationBinding(control))
                                .labelsHidden()
                                .accessibilityLabel(UntranslatedL10n.screenNativeCallAgentCenterTranslation)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                })
            }

            // The Element Call reference (`sheet/RecordingTab.tsx`) renders
            // recording as a STATUS + one action, never a toggle: a stopped
            // recording keeps `enabled == true` on purpose (what was
            // captured still gets published), so a toggle bound to
            // `enabled` could never visually turn off. The design agrees —
            // a Stop pill, not a switch.
            ListRow(kind: .custom {
                HStack(spacing: 12) {
                    NativeCallControlRowIcon(systemName: "record.circle")

                    NativeCallControlRowText(title: UntranslatedL10n.screenNativeCallAgentCenterRecording,
                                             subtitle: NativeCallAgentStatusCopy.recordingRow(agent))

                    Spacer()

                    if agent.shown.isRecording {
                        NativeCallPillButton(title: UntranslatedL10n.screenNativeCallAgentCenterStop, role: .destructive) {
                            context.send(viewAction: .setAgentSwitch(sessionID: control.sessionID,
                                                                     control: .recording,
                                                                     enabled: false))
                        }
                    } else {
                        NativeCallPillButton(title: UntranslatedL10n.screenNativeCallAgentCenterRecord, role: nil) {
                            context.send(viewAction: .setAgentSwitch(sessionID: control.sessionID,
                                                                     control: .recording,
                                                                     enabled: true))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            })

            ListRow(kind: .custom {
                HStack(spacing: 12) {
                    NativeCallControlRowIcon(systemName: "text.alignleft")

                    NativeCallControlRowText(title: UntranslatedL10n.screenNativeCallAgentCenterSummary,
                                             subtitle: NativeCallAgentStatusCopy.summaryRow(agent))

                    Spacer()

                    Toggle("", isOn: summaryBinding(control))
                        .labelsHidden()
                        .accessibilityLabel(UntranslatedL10n.screenNativeCallAgentCenterSummary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            })
        }
    }

    private func removeSection(_ control: NativeCallAgentPresentation.Control) -> some View {
        // The design's centered, icon-less destructive card.
        Section {
            ListRow(kind: .custom {
                Button(role: .destructive) {
                    context.send(viewAction: .removeAgent(sessionID: control.sessionID))
                } label: {
                    // Once the teardown is under way the button is inert —
                    // a second DELETE does no work — so it stops LOOKING
                    // armed. The spinner is the tap's receipt: the red
                    // label does not even dim when disabled, so without it
                    // pressing was visually indistinguishable from nothing.
                    HStack(spacing: 8) {
                        if isLeaving {
                            ProgressView()
                        }
                        Text(NativeCallAgentStatusCopy.removeButton(agent))
                            .font(.body)
                            .foregroundStyle(isLeaving
                                ? AnyShapeStyle(.compound.textSecondary)
                                : AnyShapeStyle(.compound.textCriticalPrimary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isEnding)
            })
        }
    }

    /// Quick OFF only: enabling needs a booth configuration, which is the
    /// editor's job — a bare `true` here would have nothing to apply.
    private func translationBinding(_ control: NativeCallAgentPresentation.Control) -> Binding<Bool> {
        Binding(get: { agent.shown.isTranslating },
                set: { isOn in
                    if !isOn {
                        context.send(viewAction: .disableAgentTranslation(sessionID: control.sessionID))
                    }
                })
    }

    /// The SHOWN truth, like the summary switch: the controller bridges an
    /// ON tap while its write is out, so turning it on reads at once; OFF
    /// reads once the server agrees, never "silent" while it may still talk;
    /// a refused write cannot leave the switch lying on.
    private func conversationBinding(_ control: NativeCallAgentPresentation.Control) -> Binding<Bool> {
        Binding(get: { agent.shown.isConversationActive },
                set: { isOn in
                    context.send(viewAction: .setAgentSwitch(sessionID: control.sessionID,
                                                             control: .conversation,
                                                             enabled: isOn))
                })
    }

    private func summaryBinding(_ control: NativeCallAgentPresentation.Control) -> Binding<Bool> {
        Binding(get: { agent.shown.isSummaryArmed },
                set: { isOn in
                    context.send(viewAction: .setAgentSwitch(sessionID: control.sessionID,
                                                             control: .summary,
                                                             enabled: isOn))
                })
    }
}

/// One foreign agent: avatar, name, status in the owner-head's voice
/// (with the critical "Recording…" appended when it also captures), the
/// wave while it airs, and the covers-me line when a booth names my voice.
private struct NativeCallForeignAgentRow: View {
    let agent: NativeCallAgentPresentation.Agent
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        HStack(spacing: 12) {
            NativeCallLetterAvatar(userID: agent.mxid,
                                   profile: context.viewState.memberProfiles[agent.mxid],
                                   fallbackName: agent.displayName,
                                   size: 36,
                                   mediaProvider: context.mediaProvider)

            VStack(alignment: .leading, spacing: 1) {
                Text(agent.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                statusText
                    .font(.footnote)
                    .lineLimit(1)

                if let coversMe = NativeCallAgentStatusCopy.coversMeLine(agent, catalog: context.viewState.agents.panel.catalog) {
                    Text(coversMe)
                        .font(.footnote)
                        .foregroundStyle(.compound.textInfoPrimary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if agent.shown.isAiring {
                NativeCallVoiceWave(userID: agent.mxid, scale: .sheet)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var statusText: Text {
        let status = NativeCallAgentStatusCopy.foreignStatus(agent,
                                                             ownUserID: context.viewState.ownUserID,
                                                             profiles: context.viewState.memberProfiles,
                                                             catalog: context.viewState.agents.panel.catalog)
        let hue: Color = switch status.hue {
        case .accent: .compound.textActionAccent
        case .critical: .compound.textCriticalPrimary
        case .secondary: .secondary
        }
        let base = Text(status.text).foregroundStyle(hue)
        guard status.appendsRecording else { return base }
        // The capture LEADS: it is the one word that must survive a
        // truncated booth list.
        return Text(UntranslatedL10n.screenNativeCallAgentCenterRecordingLive).foregroundStyle(.compound.textCriticalPrimary)
            + Text(" · ").foregroundStyle(.secondary) + base
    }
}

/// The read-only card for a foreign agent: the same head and the same
/// three rows the owner sees, minus every control — the disclosure
/// backstop for a configuration one line cannot hold.
struct NativeCallForeignAgentDetail: View {
    let agent: NativeCallAgentPresentation.Agent
    @ObservedObject var context: NativeCallScreenViewModel.Context
    @Environment(\.dismiss) private var dismiss

    /// The live agent by MXID, so the card follows the document while
    /// open — and pops when the agent leaves the roster, rather than
    /// freezing on its last words.
    private var current: NativeCallAgentPresentation.Agent? {
        context.viewState.agents.agents.first { $0.mxid == agent.mxid }
    }

    var body: some View {
        let agent = current ?? agent
        let catalog = context.viewState.agents.panel.catalog
        Form {
            Section {
                NativeCallAgentHeadRow(mxid: agent.mxid,
                                       name: agent.displayName,
                                       status: NativeCallAgentStatusCopy.headStatus(agent,
                                                                                    ownUserID: context.viewState.ownUserID,
                                                                                    profiles: context.viewState.memberProfiles,
                                                                                    catalog: context.viewState.agents.panel.catalog),
                                       isAiring: agent.shown.isAiring,
                                       context: context)
            }

            Section {
                NativeCallStatusRow(systemName: "globe",
                                    title: UntranslatedL10n.screenNativeCallAgentCenterTranslation,
                                    subtitle: NativeCallAgentStatusCopy.translationRow(agent,
                                                                                       ownUserID: context.viewState.ownUserID,
                                                                                       profiles: context.viewState.memberProfiles,
                                                                                       catalog: catalog))
                if let coversMe = NativeCallAgentStatusCopy.coversMeLine(agent, catalog: catalog) {
                    NativeCallStatusRow(systemName: "person.wave.2",
                                        title: UntranslatedL10n.screenNativeCallAgentCenterListeningSection,
                                        subtitle: coversMe)
                }
                NativeCallStatusRow(systemName: "record.circle",
                                    title: UntranslatedL10n.screenNativeCallAgentCenterRecording,
                                    subtitle: NativeCallAgentStatusCopy.recordingRow(agent))
                NativeCallStatusRow(systemName: "text.alignleft",
                                    title: UntranslatedL10n.screenNativeCallAgentCenterSummary,
                                    subtitle: NativeCallAgentStatusCopy.summaryRow(agent))
            } footer: {
                Text(UntranslatedL10n.screenNativeCallAgentCenterForeignFooter)
            }
            .listSectionSpacing(8)
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenNativeCallAgentCenterForeignDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: current == nil) { _, gone in
            if gone { dismiss() }
        }
    }
}

/// A controls-card row with nothing on the trailing edge — status only.
private struct NativeCallStatusRow: View {
    let systemName: String
    let title: String
    let subtitle: String

    var body: some View {
        ListRow(kind: .custom {
            HStack(spacing: 12) {
                NativeCallControlRowIcon(systemName: systemName)
                NativeCallControlRowText(title: title, subtitle: subtitle, subtitleLineLimit: nil)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        })
    }
}

/// The head row shared by an attached agent and one still joining: the
/// avatar, the name, the one-line status, the wave while airing.
private struct NativeCallAgentHeadRow: View {
    let mxid: String
    let name: String
    let status: String
    let isAiring: Bool
    @ObservedObject var context: NativeCallScreenViewModel.Context

    var body: some View {
        ListRow(kind: .custom {
            HStack(spacing: 12) {
                NativeCallLetterAvatar(userID: mxid,
                                       profile: context.viewState.memberProfiles[mxid],
                                       fallbackName: name,
                                       size: 36,
                                       mediaProvider: context.mediaProvider)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    // The status turns accent while the agent audibly
                    // airs — the design's blue "Speaking …" line.
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(isAiring ? Color.compound.textActionAccent : Color.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isAiring {
                    NativeCallVoiceWave(userID: mxid, scale: .sheet)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        })
    }
}

/// A session whose agent is not in the media roster: not there yet
/// ("Joining…"), or already gone while the platform still tears the session
/// down ("Removing…", walk F6). No controls: there is nothing live to
/// control, and every write would race the attach or the teardown.
private struct NativeCallAgentJoiningSection: View {
    let control: NativeCallAgentPresentation.Control
    let status: String
    @ObservedObject var context: NativeCallScreenViewModel.Context
    let showsHeader: Bool

    var body: some View {
        Section {
            NativeCallAgentHeadRow(mxid: control.agentMxid,
                                   name: context.viewState.memberProfiles[control.agentMxid]?.displayName
                                       ?? context.viewState.agents.panel.candidates.first { $0.mxid == control.agentMxid }?.displayName
                                       ?? NativeCallFallbackName.make(mxid: control.agentMxid),
                                   status: status,
                                   isAiring: false,
                                   context: context)
        } header: {
            if showsHeader {
                Text(UntranslatedL10n.screenNativeCallAgentCenterActiveSection)
            }
        }
        .compoundListSectionHeader()
    }
}

/// The controls card's leading glyph — small and quiet, like the design's
/// gray 21pt icons.
private struct NativeCallControlRowIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 24)
    }
}

/// Title over a smaller state line — every controls row reads this way.
private struct NativeCallControlRowText: View {
    let title: String
    let subtitle: String
    /// One line beside a control; nil where the row IS the information
    /// (the read-only card) and must never truncate.
    var subtitleLineLimit: Int? = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(subtitleLineLimit)
        }
    }
}

/// The design's `Stop` pill: a tinted capsule with a semibold label —
/// destructive red for stopping a capture, accent for starting one.
private struct NativeCallPillButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(role == .destructive ? Color.compound.textCriticalPrimary : Color.compound.textActionAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(role == .destructive ? Color.compound.bgCriticalSubtle : Color.compound.iconAccentPrimary.opacity(0.12),
                            in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

struct NativeCallAgentCenterSheet_Previews: PreviewProvider, TestablePreview {
    static let ownedSession = NativeAgentCenterSession(sessionID: "session-1",
                                                       agentMxid: "@assistant-alice:spiral.md",
                                                       canControl: true,
                                                       isEnding: false,
                                                       recording: .init(isEnabled: true,
                                                                        revision: 3,
                                                                        delivery: .pending,
                                                                        isStopped: false),
                                                       summary: .init(isEnabled: false,
                                                                      revision: 1,
                                                                      delivery: .notArmed,
                                                                      isStopped: false),
                                                       translation: .init(booths: [.init(speakerScope: "anyone",
                                                                                         speakerMembers: [],
                                                                                         targetLanguages: ["en"])],
                                                                          style: "simultaneous",
                                                                          source: "override",
                                                                          revision: 2),
                                                       conversation: .unknown)
    
    static let foreignSession = NativeAgentCenterSession(sessionID: "session-2",
                                                         agentMxid: "@assistant-bob:spiral.md",
                                                         canControl: false,
                                                         isEnding: false,
                                                         recording: .init(isEnabled: true,
                                                                          revision: 7,
                                                                          delivery: .delivered(target: "room"),
                                                                          isStopped: false),
                                                         summary: .init(isEnabled: true,
                                                                        revision: 2,
                                                                        delivery: .failed,
                                                                        isStopped: false),
                                                         translation: .unknown,
                                                         conversation: .unknown)
    
    static let candidate = NativeAgentCenterCandidate(id: "agent-1",
                                                      mxid: "@assistant-carol:spiral.md",
                                                      displayName: "Carol's Assistant",
                                                      avatarURL: nil,
                                                      isRoomMember: false)
    
    static let stoppedSession = NativeAgentCenterSession(sessionID: "session-3",
                                                         agentMxid: "@assistant-dan:spiral.md",
                                                         canControl: true,
                                                         isEnding: false,
                                                         recording: .init(isEnabled: true,
                                                                          revision: 4,
                                                                          delivery: .pending,
                                                                          isStopped: true),
                                                         summary: .init(isEnabled: true,
                                                                        revision: 1,
                                                                        delivery: .notArmed,
                                                                        isStopped: false),
                                                         translation: .unknown,
                                                         conversation: .unknown)
    
    static var previews: some View {
        NativeCallAgentCenterSheet(context: makeViewModel(sessions: [],
                                                          candidates: [candidate]).context)
            .previewDisplayName("Empty with candidate")
        
        NativeCallAgentCenterSheet(context: makeViewModel(sessions: [stoppedSession],
                                                          candidates: [],
                                                          documents: [stoppedSession.agentMxid: .make(summaryArmed: true)]).context)
            .previewDisplayName("Recording stopped, delivery pending")
        
        NativeCallAgentCenterSheet(context: makeViewModel(sessions: [ownedSession, foreignSession],
                                                          candidates: [candidate],
                                                          documents: [ownedSession.agentMxid: .make(languages: ["en"], recording: true, style: .simultaneous),
                                                                      foreignSession.agentMxid: .make(languages: ["en"], recording: true, style: .simultaneous)],
                                                          profiles: [foreignSession.agentMxid: .init(displayName: "Bob's Assistant")],
                                                          producedLanguages: ["en", "uk"]).context)
            .previewDisplayName("Owned and read-only sessions")
        
        ElementNavigationStack {
            NativeCallForeignAgentDetail(agent: foreignDetailViewModel.state.agents.foreignAgents[0],
                                         context: foreignDetailViewModel.context)
        }
        .previewDisplayName("Foreign agent detail")
        
        NativeCallAgentCenterSheet(context: makeViewModel(sessions: [ownedSession],
                                                          candidates: [],
                                                          error: .conflict,
                                                          documents: [ownedSession.agentMxid: .make(languages: ["en"], recording: true)]).context)
            .previewDisplayName("Conflict")

        NativeCallAgentCenterSheet(context: makeViewModel(sessions: [conversationSession],
                                                          candidates: [],
                                                          documents: [conversationSession.agentMxid: .make(recording: true, summaryArmed: true, conversation: true)],
                                                          profiles: [conversationSession.agentMxid: .init(displayName: "Erin's Assistant")]).context)
            .previewDisplayName("Conversation on")

        NativeCallAgentCenterSheet(context: makeViewModel(sessions: [conversationSession],
                                                          candidates: [],
                                                          error: .conversationRefused("the realtime conversation did not connect in time"),
                                                          documents: [conversationSession.agentMxid: .make(recording: true, summaryArmed: true)],
                                                          profiles: [conversationSession.agentMxid: .init(displayName: "Erin's Assistant")]).context)
            .previewDisplayName("Conversation off, start refused")

        NativeCallAgentCenterSheet(context: makeViewModel(sessions: [interpretingSession],
                                                          candidates: [],
                                                          documents: [interpretingSession.agentMxid: .make(languages: ["en"], style: .consecutive)],
                                                          profiles: [interpretingSession.agentMxid: .init(displayName: "Erin's Assistant")]).context)
            .previewDisplayName("Conversation unavailable while interpreting")
    }

    /// Brief 0080 — an agent that joined to record and summarise; the
    /// owner may make it talk.
    static let conversationSession = NativeAgentCenterSession(sessionID: "session-4",
                                                              agentMxid: "@assistant-erin:spiral.md",
                                                              canControl: true,
                                                              isEnding: false,
                                                              recording: .init(isEnabled: true,
                                                                               revision: 1,
                                                                               delivery: .pending,
                                                                               isStopped: false),
                                                              summary: .init(isEnabled: true,
                                                                             revision: 1,
                                                                             delivery: .notArmed,
                                                                             isStopped: false),
                                                              translation: .unknown,
                                                              conversation: .init(isAvailable: true, revision: 2))

    /// The same agent interpreting: the backend offers no conversation.
    static let interpretingSession = NativeAgentCenterSession(sessionID: "session-5",
                                                              agentMxid: "@assistant-erin:spiral.md",
                                                              canControl: true,
                                                              isEnding: false,
                                                              recording: .init(isEnabled: false,
                                                                               revision: 0,
                                                                               delivery: .notArmed,
                                                                               isStopped: false),
                                                              summary: .init(isEnabled: false,
                                                                             revision: 0,
                                                                             delivery: .notArmed,
                                                                             isStopped: false),
                                                              translation: .init(booths: [.init(speakerScope: "anyone",
                                                                                                speakerMembers: [],
                                                                                                targetLanguages: ["en"])],
                                                                                 style: "consecutive",
                                                                                 source: "override",
                                                                                 revision: 1),
                                                              conversation: .init(isAvailable: false, revision: 0))
    
    /// Brief 0066 — an Interpreter with two booths, one naming us: the
    /// read-only card phrases every booth and what it means for our ears.
    static let foreignDetailViewModel = makeViewModel(sessions: [foreignSession],
                                                      candidates: [],
                                                      documents: [foreignSession.agentMxid: .make(languages: ["en", "uk"],
                                                                                                  summaryArmed: true,
                                                                                                  style: .consecutive,
                                                                                                  booths: [.init(coverage: .members(["@alice:spiral.md"]), targetLanguages: ["en"]),
                                                                                                           .init(coverage: .exceptMembers(["@bob:spiral.md"]), targetLanguages: ["uk"])])],
                                                      profiles: [foreignSession.agentMxid: .init(displayName: "Bob's Assistant"),
                                                                 "@bob:spiral.md": .init(displayName: "Bohdan")],
                                                      producedLanguages: ["en", "uk"])

    /// Every session's agent is IN THE ROSTER (the presentation lists
    /// nothing else) and says what it does through its DOCUMENT — the REST
    /// session is control only, exactly as in production. The local user
    /// is `@alice:spiral.md`, so "you" phrasing has someone to be.
    static func makeViewModel(sessions: [NativeAgentCenterSession],
                              candidates: [NativeAgentCenterCandidate],
                              error: NativeAgentCenterError? = nil,
                              documents: [String: SpiralAgentStateReader.AgentClaim] = [:],
                              profiles: [String: NativeCallMemberProfile] = [:],
                              producedLanguages: [String] = []) -> NativeCallScreenViewModel {
        let rtcSession = MatrixRTCSessionMock()
        rtcSession.underlyingOwnIdentity = "@alice:spiral.md:DEVICE"
        rtcSession.underlyingUpdates = Empty().eraseToAnyPublisher()
        
        let viewModel = NativeCallScreenViewModel(session: NativeCallSession(rtcSession: rtcSession,
                                                                             isRoomEncrypted: true,
                                                                             notifyRoom: false,
                                                                             configuration: .init(media: .audio, scope: .group),
                                                                             transport: NativeCallScreen_Previews.makePreviewTransport()),
                                                  callKitService: CallKitServiceMock(.init()),
                                                  agentCenter: NativeAgentCenterController(agentPlatformService: nil,
                                                                                           roomID: "!room:spiral.md",
                                                                                           roomMemberMxids: { [] },
                                                                                           inviteAgent: { _ in false }),
                                                  appMediator: AppMediatorMock(.init()),
                                                  isVideoCall: false,
                                                  roomID: "!room:spiral.md",
                                                  roomName: "Native call")
        viewModel.state.agentCenter = NativeAgentCenterSnapshot(isAvailable: true,
                                                                isLoading: false,
                                                                sessions: sessions,
                                                                candidates: candidates,
                                                                availableLanguages: [.init(code: "en", label: "English"),
                                                                                     .init(code: "uk", label: "Ukrainian")],
                                                                lastError: error)
        // Phase 2 — the WHAT YOU HEAR switch resolves against the produced
        // union.
        if !producedLanguages.isEmpty {
            viewModel.state.listening = NativeCallListeningState(producedLanguages: producedLanguages,
                                                                 channel: .everything)
        }
        viewModel.state.callState = .connected
        viewModel.state.participants = [NativeCallParticipant(id: "@alice:spiral.md:DEVICE",
                                                              userID: "@alice:spiral.md",
                                                              role: .human,
                                                              mediaState: .connected,
                                                              isSpeaking: false,
                                                              isAudioEnabled: true,
                                                              isLocal: true)] + sessions.map { session in
            NativeCallParticipant(id: "\(session.agentMxid):DEVICE",
                                  userID: session.agentMxid,
                                  role: .agent,
                                  mediaState: .connected,
                                  isSpeaking: false,
                                  isAudioEnabled: true,
                                  isLocal: false)
        }
        viewModel.state.memberProfiles = profiles
        viewModel.state.agentClaims.documents = documents
        return viewModel
    }
}
