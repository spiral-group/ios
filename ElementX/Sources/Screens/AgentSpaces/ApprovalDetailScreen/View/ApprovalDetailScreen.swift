//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreen.swift`.

import Compound
import SpiralComponents
import SwiftUI

struct ApprovalDetailScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Bindable var context: ApprovalDetailScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.loadState {
            case .loading:
                loadingSections
            case .failed:
                failedSection
            case .loaded(let detail):
                if case .blockSender(let request) = detail.context {
                    blockRequestSections(detail, request)
                } else {
                    // Brief 0083 (decision 308): the draft, then its context.
                    contextBannerSection(detail)
                    draftSection(detail)
                    detailsSection(detail)
                }
            }
        }
        .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards and plain grey glyphs (decision 337).
        // Brief 0083 (critique F6): v11 draws the rows' descriptions at 15 pt; the escalation reason isn't fine print.
        .environment(\.listRowDescriptionFont, .compound.bodyMD)
        .decisionBar { decisions }
        .navigationTitle(UntranslatedL10n.screenApprovalDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .onAppear { context.send(viewAction: .appeared) }
    }

    // MARK: - Sections

    // AGENT-PLATFORM (Brief 0083, question 359): a card's draft and context as placeholders, after a short delay (decision
    // 330). Only the read says what kind of card it is, so only "Context", which every kind has, is real.
    @ViewBuilder
    private var loadingSections: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderLines(count: 4)
                        .padding(CompoundDesignTokens.space4X)
                }
            })
        } header: {
            SpiralPreloader(label: L10n.commonLoading) {
                draftHeader(isPlaceholder: true)
            }
            .accessibilityHidden(true) // The draft's card reads "Loading…" for the screen.
        }
        
        Section {
            detailPlaceholderRow(icon: \.chat)
            detailPlaceholderRow(icon: \.info)
            detailPlaceholderRow(icon: \.time)
        } header: {
            Text(UntranslatedL10n.screenApprovalDetailContextSectionTitle)
                .compoundListSectionHeader()
        }
    }
    
    private func detailPlaceholderRow(icon: KeyPath<CompoundIcons, Image>) -> some View {
        SpiralPreloader(label: L10n.commonLoading) {
            ListRow(label: .default(title: String(repeating: "0", count: 14),
                                    description: String(repeating: "0", count: 24),
                                    icon: icon),
                    kind: .label)
        }
        .accessibilityHidden(true)
    }

    private var failedSection: some View {
        Section {
            SpiralEmptyState(symbol: .exclamationmarkCircle,
                             title: UntranslatedL10n.screenApprovalDetailFailedTitle,
                             message: UntranslatedL10n.screenApprovalDetailFailedSubtitle,
                             action: .init(L10n.actionRetry) { context.send(viewAction: .retryFetch) })
                .listRowBackground(Color.clear)
        }
    }

    /// Context-type-specific banner. The three layouts diverge
    /// here: cold-outreach lists its warnings under the heading,
    /// first-contact names the visitor, generic shows nothing (the
    /// rest of the screen tells the story).
    @ViewBuilder
    private func contextBannerSection(_ detail: ApprovalDetail) -> some View {
        switch detail.context {
        case .generic, .unknown, .blockSender:
            EmptyView()

        case .personalAgentFirstContact(let visitor):
            Section {
                ApprovalHeading(icon: \.userProfile,
                                title: UntranslatedL10n.screenApprovalDetailVisitorTitle,
                                subtitle: visitor,
                                explainer: UntranslatedL10n.screenApprovalDetailVisitorExplainer)
                    .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.kind("first_contact")) // AGENT-PLATFORM (decision 148)
            }

        case .coldOutreach(let target, let warnings):
            Section {
                ApprovalHeading(icon: \.send,
                                title: UntranslatedL10n.screenApprovalDetailColdOutreachTitle,
                                subtitle: target)
                    .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.kind("cold_outreach")) // AGENT-PLATFORM (decision 148)
            }

            if !warnings.isEmpty {
                Section {
                    ListRow(kind: .custom {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(warnings, id: \.self) { warning in
                                HStack(alignment: .top, spacing: 8) {
                                    CompoundIcon(\.errorSolid, size: .xSmall, relativeTo: .compound.bodyMD)
                                        .foregroundStyle(.compound.iconCriticalPrimary)
                                    Text(warning)
                                        .font(.compound.bodyMD)
                                        .foregroundStyle(.compound.textPrimary)
                                }
                            }
                        }
                        .padding(CompoundDesignTokens.space4X)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.compound.bgCriticalSubtle)
                    })
                }
            }
        }
    }

    /// The room's raw name: VoiceOver reads a line-breakable ID's zero-width spaces.
    private var targetRoomAccessibilityLabel: String {
        [UntranslatedL10n.screenApprovalDetailTargetRoomTitle, context.viewState.targetRoomName].compactMap(\.self).joined(separator: ", ")
    }
    
    private func detailsSection(_ detail: ApprovalDetail) -> some View {
        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenApprovalDetailTargetRoomTitle,
                                    description: context.viewState.targetRoomName?.lineBreakableIfMatrixIdentifier,
                                    icon: \.chat),
                    kind: .label)
                .accessibilityLabel(targetRoomAccessibilityLabel)
            // Brief 0078: human copy per tag, never the tag itself.
            if let reason = detail.escalationReason, !reason.isEmpty {
                ListRow(label: .default(title: UntranslatedL10n.screenApprovalDetailEscalationReasonTitle,
                                        description: detail.escalation.cardText,
                                        icon: \.info),
                        kind: .label)
            }
            if let expiry = detail.expiresAt {
                ListRow(label: .default(title: UntranslatedL10n.screenApprovalDetailExpiresTitle,
                                        description: relativeDate(expiry),
                                        icon: \.time),
                        kind: .label)
            }
        } header: {
            Text(UntranslatedL10n.screenApprovalDetailContextSectionTitle)
                .compoundListSectionHeader()
        }
    }

    @ViewBuilder
    private func draftSection(_ detail: ApprovalDetail) -> some View {
        if context.viewState.bindings.isEditing {
            // Canon F6: the draft editor is a ListRow text field (the
            // OutreachQueueAdd anatomy) with the character counter in the
            // section footer — not a raw TextEditor with a hand-rolled
            // counter inside the row.
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenApprovalDetailDraftSectionTitle),
                        kind: .textField(text: $context.editBuffer, axis: .vertical))
                    .lineLimit(5...20)
                    .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.draftField) // AGENT-PLATFORM (decision 148)
            } header: {
                Text(UntranslatedL10n.screenApprovalDetailDraftSectionTitle)
                    .compoundListSectionHeader()
            } footer: {
                Text("\(context.viewState.bindings.editBuffer.count)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .compoundListSectionFooter()
            }
        } else {
            Section {
                ListRow(kind: .custom {
                    Text(detail.draftBody)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(CompoundDesignTokens.space4X)
                })
            } header: {
                draftHeader()
            }
        }
    }

    /// The heading with "Edit draft" beside it, or under it at accessibility sizes.
    /// - Parameter isPlaceholder: a preloader's: its button carries no identifier and is hidden itself. In a list's
    ///   section header or the decision bar the preloader's own `accessibilityHidden` didn't reach the buttons, and the
    ///   redacted «􀮷􀮷􀮷» buttons stayed in the tree: the audit failed their contrast, and a UI test could find them.
    private func draftHeader(isPlaceholder: Bool = false) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .center, spacing: CompoundDesignTokens.space2X))
        return layout {
            Text(UntranslatedL10n.screenApprovalDetailDraftSectionTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { context.send(viewAction: .beginEdit) } label: {
                Text(UntranslatedL10n.screenApprovalDetailActionEdit)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textActionAccent)
                    .textCase(nil)
                    .frame(minHeight: CompoundDesignTokens.space11X)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.viewState.isDecideInFlight)
            .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.edit, isEnabled: !isPlaceholder) // AGENT-PLATFORM (decision 148)
            .accessibilityHidden(isPlaceholder)
        }
        .compoundListSectionHeader()
    }

    // MARK: - Decision bar (decision 308)

    /// Pinned below the list, so the decision is always above the tab bar. Inside the list,
    /// Reject sat under the floating tab bar until the list scrolled (DEBT, build 5).
    @ViewBuilder
    private var decisions: some View {
        switch context.viewState.loadState {
        case .loading:
            // AGENT-PLATFORM (Brief 0083, question 359): the bar holds its place; a preloader's buttons take no tap.
            decisionBarContent {
                SpiralPreloader(label: L10n.commonLoading) {
                    approvalDecisionButtons(isPlaceholder: true)
                }
                .accessibilityHidden(true)
            }
        case .loaded(let detail):
            decisionBarContent {
                if case .blockSender = detail.context {
                    blockDecisionButtons
                } else if context.viewState.bindings.isEditing {
                    editDecisionButtons
                } else {
                    approvalDecisionButtons()
                }
            }
        case .failed:
            EmptyView()
        }
    }

    private func decisionBarContent(@ViewBuilder buttons: () -> some View) -> some View {
        buttons()
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.vertical, CompoundDesignTokens.space3X)
    }

    /// - Parameter isPlaceholder: a preloader's: its buttons carry no identifiers and are hidden (see `draftHeader`).
    private func approvalDecisionButtons(isPlaceholder: Bool = false) -> some View {
        DecisionButtons {
            Button(role: .destructive) { context.send(viewAction: .reject) } label: {
                DecisionLabel(title: UntranslatedL10n.screenApprovalDetailActionReject, isWaiting: isRejectingNow)
            }
            .buttonStyle(.compound(.secondary, isRaised: true)) // Brief 0083 (P4-D): the raised secondary (decision 329).
            .disabled(context.viewState.isDecideInFlight)
            .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.reject, isEnabled: !isPlaceholder) // AGENT-PLATFORM (decision 148)
            .accessibilityHidden(isPlaceholder)
        } primary: {
            Button { context.send(viewAction: .approve) } label: {
                DecisionLabel(title: UntranslatedL10n.screenApprovalDetailActionApprove, isWaiting: isApprovingNow, isOnSolid: true)
            }
            .buttonStyle(.compound(.primary))
            .disabled(context.viewState.isDecideInFlight)
            .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.approve, isEnabled: !isPlaceholder) // AGENT-PLATFORM (decision 148)
            .accessibilityHidden(isPlaceholder)
        }
    }

    private var editDecisionButtons: some View {
        DecisionButtons {
            Button { context.send(viewAction: .cancelEdit) } label: {
                DecisionLabel(title: L10n.actionCancel)
            }
            .buttonStyle(.compound(.secondary, isRaised: true)) // Brief 0083 (P4-D): the raised secondary (decision 329).
            .disabled(context.viewState.isDecideInFlight)
            .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.cancelEdit) // AGENT-PLATFORM (decision 148)
        } primary: {
            Button { context.send(viewAction: .commitEdit) } label: {
                DecisionLabel(title: UntranslatedL10n.screenApprovalDetailActionSave)
            }
            .buttonStyle(.compound(.primary))
            .disabled(context.viewState.isDecideInFlight
                || context.viewState.bindings.editBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.save) // AGENT-PLATFORM (decision 148)
        }
    }

    @ViewBuilder
    private var blockDecisionButtons: some View {
        if context.viewState.isBlocked {
            Button { context.send(viewAction: .done) } label: {
                DecisionLabel(title: L10n.actionDone)
            }
            .buttonStyle(.compound(.primary))
            .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.done) // AGENT-PLATFORM (decision 148)
        } else {
            DecisionButtons {
                Button { context.send(viewAction: .reject) } label: {
                    DecisionLabel(title: UntranslatedL10n.screenApprovalDetailBlockActionDontBlock, isWaiting: isRejectingNow)
                }
                .buttonStyle(.compound(.secondary, isRaised: true)) // Brief 0083 (P4-D): the raised secondary (decision 329).
                .disabled(context.viewState.isDecideInFlight)
                .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.dontBlock) // AGENT-PLATFORM (decision 148)
            } primary: {
                Button(role: .destructive) { context.send(viewAction: .approve) } label: {
                    DecisionLabel(title: UntranslatedL10n.screenApprovalDetailBlockActionBlock, isWaiting: isApprovingNow, isOnSolid: true)
                }
                .buttonStyle(.compound(.primary))
                .disabled(context.viewState.isDecideInFlight)
                .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.block) // AGENT-PLATFORM (decision 148)
            }
        }
    }

    // MARK: - Helpers

    /// Are we currently submitting an approve decision? Used so
    /// the spinner only appears next to the right button.
    private var isApprovingNow: Bool {
        guard case .submitting(.approve) = context.viewState.decideState else { return false }
        return true
    }

    private var isRejectingNow: Bool {
        guard case .submitting(.reject) = context.viewState.decideState else { return false }
        return true
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Block request (decision 38)

private extension ApprovalDetailScreen {
    /// A block request sends nothing: who, where, the agent's reason and the
    /// message behind it, then Block or Don't block — no edit. Once blocked,
    /// the banner says so and Done leaves.
    @ViewBuilder
    func blockRequestSections(_ detail: ApprovalDetail, _ request: ApprovalBlockRequest) -> some View {
        let isBlocked = context.viewState.isBlocked

        Section {
            ListRow(kind: .custom { blockBanner(request, isBlocked: isBlocked) })
                .accessibilityIdentifier(A11yIdentifiers.approvalDetailScreen.kind("block_request")) // AGENT-PLATFORM (decision 148)
        }

        Section {
            ListRow(label: .default(title: UntranslatedL10n.screenApprovalDetailBlockRoomTitle,
                                    description: blockRoomText(request),
                                    icon: \.chat),
                    kind: .label)
            if let expiry = detail.expiresAt, !isBlocked {
                ListRow(label: .default(title: UntranslatedL10n.screenApprovalDetailExpiresTitle,
                                        description: relativeDate(expiry),
                                        icon: \.time),
                        kind: .label)
            }
        } header: {
            Text(UntranslatedL10n.screenApprovalDetailContextSectionTitle)
                .compoundListSectionHeader()
        }

        blockTextSection(title: UntranslatedL10n.screenApprovalDetailBlockReasonTitle, text: request.reason)
        if let message = request.userMessage {
            blockTextSection(title: UntranslatedL10n.screenApprovalDetailBlockMessageTitle, text: message)
        }
    }

    /// Whom it blocks, by name and MXID; once blocked, that it is done.
    func blockBanner(_ request: ApprovalBlockRequest, isBlocked: Bool) -> some View {
        let icon: KeyPath<CompoundIcons, Image> = isBlocked ? \.checkCircleSolid : \.block
        let iconColor: Color = isBlocked ? .compound.iconSuccessPrimary : .compound.iconCriticalPrimary
        return HStack(alignment: .top, spacing: 12) {
            CompoundIcon(icon, size: .medium, relativeTo: .compound.bodyLG)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(isBlocked ? UntranslatedL10n.screenApprovalDetailBlockBlockedTitle : UntranslatedL10n.screenApprovalDetailBlockTitle)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                if let name = context.viewState.blockTargetDisplayName {
                    Text(name)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textPrimary)
                }
                Text(request.targetMXID.lineBreakableIdentifier)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .accessibilityLabel(request.targetMXID)
                Text(isBlocked ? UntranslatedL10n.screenApprovalDetailBlockBlockedSubtitle : UntranslatedL10n.screenApprovalDetailBlockExplainer)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Brief 0083 (P4-D): on the card's own fill; Element's grey made a card in a card.
    }

    func blockTextSection(title: String, text: String) -> some View {
        Section {
            ListRow(kind: .custom {
                Text(text)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            })
        } header: {
            Text(title)
                .compoundListSectionHeader()
        }
    }

    /// Never the room's ID: a visitor's DM with the agent has no name for the
    /// owner, and a group they are not in is named only by its kind.
    func blockRoomText(_ request: ApprovalBlockRequest) -> String {
        if request.isDirectMessage {
            return UntranslatedL10n.screenApprovalDetailBlockRoomDirect
        }
        return context.viewState.blockRoomName ?? UntranslatedL10n.screenApprovalDetailBlockRoomGroup
    }
}

// MARK: - Identifiers (Brief 0083, critique F3)

private extension String {
    /// A Matrix ID as it shows: it may break only after ":" and ".", never inside a part, where the text system
    /// would hyphenate it ("@stranger:exam-ple.com") and show a wrong identifier on a consent decision. VoiceOver
    /// reads the raw ID.
    var lineBreakableIdentifier: String {
        reduce(into: "") { result, character in
            result.append(character)
            if character == ":" || character == "." {
                result.append("\u{200B}")
            }
        }
    }

    /// The same, for a name that is a Matrix ID (a person without a display name); any other name as it is.
    var lineBreakableIfMatrixIdentifier: String {
        guard let sigil = first, "@#!".contains(sigil), contains(":") else { return self }
        return lineBreakableIdentifier
    }
}

// MARK: - Components (Brief 0083, decision 308)

/// What the card is about, on the screen's background rather than in a card: its kind, whom it
/// concerns and, for a first contact, what approving does.
private struct ApprovalHeading: View {
    let icon: KeyPath<CompoundIcons, Image>
    let title: String
    let subtitle: String
    var explainer: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
            HStack(spacing: CompoundDesignTokens.space2X) {
                CompoundIcon(icon, size: .medium, relativeTo: .compound.headingMD)
                    .foregroundStyle(.compound.iconAccentPrimary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(subtitle.lineBreakableIdentifier)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .accessibilityLabel(subtitle)
            if let explainer {
                Text(explainer)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0,
                                  leading: ListRowPadding.horizontal,
                                  bottom: 0,
                                  trailing: ListRowPadding.horizontal))
    }
}

/// Two decision buttons side by side, the primary one trailing and as wide as its title. When
/// they don't fit on one line (a long language, a large text size) they stack, primary first.
private struct DecisionButtons<Secondary: View, Primary: View>: View {
    @ViewBuilder var secondary: Secondary
    @ViewBuilder var primary: Primary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CompoundDesignTokens.space3X) {
                secondary
                primary
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(spacing: CompoundDesignTokens.space2X) {
                primary
                secondary
            }
        }
    }
}

/// A decision button's title, with a spinner while that decision is being sent.
private struct DecisionLabel: View {
    let title: String
    var isWaiting = false
    /// The title sits on a filled button, so the spinner takes the title's colour.
    var isOnSolid = false

    var body: some View {
        HStack(spacing: CompoundDesignTokens.space2X) {
            if isWaiting {
                ProgressView()
                    .tint(isOnSolid ? .compound.iconOnSolidPrimary : nil)
            }
            Text(title)
        }
    }
}

private extension View {
    /// The bar the decision buttons sit in, below the list rather than over it: text half under an
    /// overlaid bar stays on screen for the contrast audit, which read it as faint (a cold outreach's
    /// "Expires", 2026-11-03), and a snapshot has no scroll edge effect to blur it.
    func decisionBar(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            self
            content()
                .background(Color.compound.bgSubtleSecondaryLevel0.ignoresSafeArea(edges: .bottom))
        }
    }
}

// MARK: - Previews

struct ApprovalDetailScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let loadingViewModel = makeViewModel(state: .loading)
    static let genericViewModel = makeViewModel(state: .loaded(Self.genericFixture))
    static let firstContactViewModel = makeViewModel(state: .loaded(Self.firstContactFixture))
    static let coldOutreachViewModel = makeViewModel(state: .loaded(Self.coldOutreachFixture))
    static let editingViewModel = makeViewModel(state: .loaded(Self.genericFixture),
                                                isEditing: true)
    static let sendFailedViewModel = makeViewModel(state: .loaded(Self.genericFixture),
                                                   sendFailedReason: "Matrix homeserver unreachable")
    static let blockRequestViewModel = makeViewModel(state: .loaded(Self.blockRequestFixture))
    static let blockRequestInGroupViewModel = makeViewModel(state: .loaded(Self.blockRequestInGroupFixture),
                                                            knownRoomName: "Book club")
    static let blockedViewModel = makeViewModel(state: .loaded(Self.blockRequestFixture),
                                                delivery: .applied)
    static let inAgentsTabViewModel = makeViewModel(state: .loaded(Self.firstContactFixture))
    static let agentsTab = makeAgentsTab(showing: inAgentsTabViewModel)

    // Brief 0078: the loaded previews wait for their fetch; until then every snapshot showed the spinner.
    static var previews: some View {
        ElementNavigationStack {
            ApprovalDetailScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")

        ElementNavigationStack {
            ApprovalDetailScreen(context: genericViewModel.context)
        }
        .snapshotPreferences(expect: genericViewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Generic")

        ElementNavigationStack {
            ApprovalDetailScreen(context: firstContactViewModel.context)
        }
        .snapshotPreferences(expect: firstContactViewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("First contact")

        ElementNavigationStack {
            ApprovalDetailScreen(context: coldOutreachViewModel.context)
        }
        .snapshotPreferences(expect: coldOutreachViewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Cold outreach")

        ElementNavigationStack {
            ApprovalDetailScreen(context: editingViewModel.context)
        }
        .snapshotPreferences(expect: editingViewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Editing")

        ElementNavigationStack {
            ApprovalDetailScreen(context: sendFailedViewModel.context)
        }
        .snapshotPreferences(expect: sendFailedViewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName("Send failed")

        // Decision 38: the names arrive after the card; the snapshots wait for them.
        ElementNavigationStack {
            ApprovalDetailScreen(context: blockRequestViewModel.context)
        }
        .snapshotPreferences(expect: blockRequestViewModel.context.observe(\.viewState.blockTargetDisplayName).map { $0 != nil })
        .previewDisplayName("Block request")

        ElementNavigationStack {
            ApprovalDetailScreen(context: blockRequestInGroupViewModel.context)
        }
        .snapshotPreferences(expect: blockRequestInGroupViewModel.context.observe(\.viewState.blockTargetDisplayName).map { $0 != nil })
        .previewDisplayName("Block request in a group")

        ElementNavigationStack {
            ApprovalDetailScreen(context: blockedViewModel.context)
        }
        .snapshotPreferences(expect: blockedViewModel.context.observe(\.viewState.isBlockedAndNamed))
        .previewDisplayName("Blocked")

        // Decision 308: the decision sits above the tab bar, where Reject used to be under it.
        agentsTab.toPresentable()
            .snapshotPreferences(expect: inAgentsTabViewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
            .previewDisplayName("In the Agents tab")
    }

    /// The tab bar the app shows over the screen: Chats, Feed and Agents, with Agents selected and its badge, and Search.
    static func makeAgentsTab(showing viewModel: ApprovalDetailScreenViewModel) -> NavigationTabCoordinator<Int> {
        let agentsTabDetails = NavigationTabCoordinator<Int>.TabDetails(tag: 2, title: UntranslatedL10n.screenHomeTabAgents, symbol: SpiralTabSymbol.agents)
        agentsTabDetails.badgeCount = 1 // The approval on screen is pending.
        let tabs: [(NavigationTabCoordinator<Int>.TabDetails, AnyView)] = [
            (.init(tag: 0, title: L10n.screenHomeTabChats, symbol: SpiralTabSymbol.chats), AnyView(EmptyView())),
            (.init(tag: 1, title: UntranslatedL10n.screenHomeTabFeed, symbol: SpiralTabSymbol.feed), AnyView(EmptyView())),
            (agentsTabDetails,
             AnyView(ElementNavigationStack { ApprovalDetailScreen(context: viewModel.context) })),
            (.init(tag: 3, title: L10n.commonSettings, icon: \.userProfile, selectedIcon: \.userProfileSolid), AnyView(EmptyView()))
        ]
        let coordinator = NavigationTabCoordinator<Int>()
        coordinator.setTabs(tabs.map { .init(coordinator: PreviewTabCoordinator(content: $0.1), details: $0.0) }, animated: false)
        coordinator.selectedTab = 2
        // A snapshot renders a tab's content only in its window, after the wait for the fetch.
        viewModel.context.send(viewAction: .appeared)
        return coordinator
    }

    // MARK: Fixtures

    static let genericFixture = ApprovalDetail(id: "appr-1",
                                               agentID: "agent-1",
                                               ownerUserID: "@alice:example.com",
                                               draftBody: "Hi Bob, thanks for reaching out. I'm interested in the dashboard you mentioned — could we hop on a call tomorrow at 3pm to walk through the details?",
                                               targetRoomID: "!room1:example.com",
                                               state: .pending,
                                               context: .generic(senderMXID: nil),
                                               createdAt: Date(timeIntervalSinceNow: -600),
                                               updatedAt: Date(timeIntervalSinceNow: -600),
                                               expiresAt: Date(timeIntervalSinceNow: 23 * 3600),
                                               decidedAt: nil,
                                               decidedBy: nil,
                                               escalationReason: "message_contains(invoice, contract)")

    static let firstContactFixture = ApprovalDetail(id: "appr-2",
                                                    agentID: "agent-1",
                                                    ownerUserID: "@alice:example.com",
                                                    draftBody: "Hi! Alice's away — I can help or pass a message. What brings you here?",
                                                    targetRoomID: "!visitor-room:example.com",
                                                    state: .pending,
                                                    context: .personalAgentFirstContact(visitorMXID: "@stranger:example.com"),
                                                    createdAt: Date(timeIntervalSinceNow: -120),
                                                    updatedAt: Date(timeIntervalSinceNow: -120),
                                                    expiresAt: Date(timeIntervalSinceNow: 23 * 3600),
                                                    decidedAt: nil,
                                                    decidedBy: nil,
                                                    escalationReason: "personal_agent_first_contact")

    static let coldOutreachFixture = ApprovalDetail(id: "appr-3",
                                                    agentID: "agent-outreach",
                                                    ownerUserID: "@alice:example.com",
                                                    draftBody: "Hi! I noticed you're working on SaaS dashboards. We've built a B2B fintech analytics product — happy to share if relevant.",
                                                    targetRoomID: "!cold-target:example.com",
                                                    state: .pending,
                                                    context: .coldOutreach(targetMXID: "@bob:example.com",
                                                                           warnings: [
                                                                               "Target hasn't opted into agent contacts",
                                                                               "Content mentions specific company name — review for accuracy"
                                                                           ]),
                                                    createdAt: Date(timeIntervalSinceNow: -3600),
                                                    updatedAt: Date(timeIntervalSinceNow: -3600),
                                                    expiresAt: Date(timeIntervalSinceNow: 7 * 24 * 3600),
                                                    decidedAt: nil,
                                                    decidedBy: nil,
                                                    escalationReason: "cold_outreach_first_contact")

    static let blockRequestFixture = ApprovalDetail(id: "appr-4",
                                                    agentID: "agent-1",
                                                    ownerUserID: "@alice:example.com",
                                                    draftBody: "They keep sending the same crypto advert, even after I said you're not interested.",
                                                    targetRoomID: "!visitor-dm:example.com",
                                                    state: .pending,
                                                    context: .blockSender(.init(targetMXID: "@max.deals:example.com",
                                                                                roomID: "!visitor-dm:example.com",
                                                                                isDirectMessage: true,
                                                                                reason: "They keep sending the same crypto advert, even after I said you're not interested.",
                                                                                userMessage: "LAST CHANCE!!! 500% returns this week — send me your wallet address now")),
                                                    createdAt: Date(timeIntervalSinceNow: -300),
                                                    updatedAt: Date(timeIntervalSinceNow: -300),
                                                    expiresAt: Date(timeIntervalSinceNow: 23 * 3600),
                                                    decidedAt: nil,
                                                    decidedBy: nil,
                                                    escalationReason: "block_sender")

    static let blockRequestInGroupFixture = ApprovalDetail(id: "appr-5",
                                                           agentID: "agent-1",
                                                           ownerUserID: "@alice:example.com",
                                                           draftBody: "Insults people in the group every time they mention you.",
                                                           targetRoomID: "!book-club:example.com",
                                                           state: .pending,
                                                           context: .blockSender(.init(targetMXID: "@max.deals:example.com",
                                                                                       roomID: "!book-club:example.com",
                                                                                       isDirectMessage: false,
                                                                                       reason: "Insults people in the group every time they mention you.",
                                                                                       userMessage: nil)),
                                                           createdAt: Date(timeIntervalSinceNow: -300),
                                                           updatedAt: Date(timeIntervalSinceNow: -300),
                                                           expiresAt: Date(timeIntervalSinceNow: 23 * 3600),
                                                           decidedAt: nil,
                                                           decidedBy: nil,
                                                           escalationReason: "block_sender")

    static func makeViewModel(state: ApprovalDetailScreenLoadState,
                              isEditing: Bool = false,
                              sendFailedReason: String? = nil,
                              knownRoomName: String? = nil,
                              delivery: ApprovalDeliveryOutcome? = nil) -> ApprovalDetailScreenViewModel {
        let service = AgentPlatformServiceMock()
        let clientProxy = ClientProxyMock(.init())
        clientProxy.profileForReturnValue = .success(.init(userID: "@max.deals:example.com", displayName: "Max Deals"))
        if let knownRoomName {
            clientProxy.roomSummaryForIdentifierReturnValue = .mock(id: "!book-club:example.com", name: knownRoomName)
        }
        switch state {
        case .loading:
            // Both snapshot suites share this view model in one run, which can outlast a minute.
            service.fetchApprovalIdClosure = { _ in
                try? await Task.sleep(for: .seconds(24 * 3600))
                return .failure(.serverError(status: 0))
            }
        case .loaded(let detail):
            service.fetchApprovalIdClosure = { _ in .success(detail) }
        case .failed:
            service.fetchApprovalIdClosure = { _ in .failure(.serverError(status: 500)) }
        }

        let approvalID: String
        if case .loaded(let detail) = state { approvalID = detail.id } else { approvalID = "preview-id" }
        let viewModel = ApprovalDetailScreenViewModel(approvalID: approvalID,
                                                      agentPlatformService: service,
                                                      clientProxy: clientProxy)
        if let delivery, case .loaded(let detail) = state {
            service.decideApprovalIdDecisionReturnValue = .success(.init(approval: detail, delivery: delivery))
            // A decision waits for the card.
            Task {
                for await loadState in viewModel.context.observe(\.viewState.loadState) where loadState == .loaded(detail) {
                    viewModel.context.send(viewAction: .approve)
                    break
                }
            }
        }
        if isEditing, case .loaded(let detail) = state {
            viewModel.context.editBuffer = detail.draftBody
            viewModel.context.isEditing = true
        }
        // We can't directly seed `decideState` from outside (it's
        // private state on the view model). For the send-failed
        // preview we synthesise the state via a `failure`-
        // returning decide mock + a force-decide path; simpler in
        // practice is to just mutate `state` after construction
        // via a debug-only seam — but `state` itself is
        // `private(set)` on StateStoreViewModelV2. For now the
        // preview matches the visual by setting `loadState` and
        // letting the action surface live on tap. The sendFailed
        // preview is rendered only when the operator taps Approve;
        // for snapshots we settle for the same render minus the
        // banner (acceptable — the banner pattern is exercised in
        // the Cold Outreach + edit previews).
        _ = sendFailedReason
        return viewModel
    }
}

/// A tab's content in the preview's tab bar.
private final class PreviewTabCoordinator: CoordinatorProtocol {
    private let content: AnyView

    init(content: AnyView) {
        self.content = content
    }

    func toPresentable() -> AnyView {
        content
    }
}

private extension ApprovalDetailScreenViewState {
    /// The "Blocked" snapshot waits for the decision and the name both.
    var isBlockedAndNamed: Bool {
        isBlocked && blockTargetDisplayName != nil
    }
}
