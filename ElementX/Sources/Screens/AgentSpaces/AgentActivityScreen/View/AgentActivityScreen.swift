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

struct AgentActivityScreen: View {
    @Bindable var context: AgentActivityScreenViewModel.Context

    var body: some View {
        SwiftUI.TimelineView(AgentRelativeTime.refreshSchedule) { timeline in
            Form {
                switch context.viewState.listState {
                case .loading:
                    skeletonSection
                case .loaded where context.viewState.isEmpty:
                    emptySection
                case .loaded(let items, _):
                    rowsSection(items, now: timeline.date)
                    if let sentinel = context.viewState.sentinel {
                        sentinelSection(sentinel)
                    }
                case .failed:
                    errorSection
                }
            }
            .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards and plain grey glyphs (decision 337).
        }
        .navigationTitle(UntranslatedL10n.screenAgentActivityTitle)
        .navigationBarTitleDisplayMode(.inline)
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .toolbar { filterToolbarItem }
    }

    // MARK: - Toolbar

    private var filterToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(UntranslatedL10n.screenAgentActivityFilterMenuTitle,
                       selection: Binding(get: { context.viewState.filter },
                                          set: { context.send(viewAction: .selectFilter($0)) })) {
                    ForEach(ActionOutcomeFilter.offered, id: \.self) { filter in
                        Text(Self.filterLabel(filter))
                            .tag(filter)
                    }
                }
            } label: {
                CompoundIcon(\.filter, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconPrimary)
            }
            .accessibilityLabel(UntranslatedL10n.screenAgentActivityFilterMenuTitle)
        }
    }

    // MARK: - Sections

    // Decision 330: the activity's rows as placeholders, after a short delay.
    private var skeletonSection: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderRows(count: 5, leading: .icon)
                }
            })
        }
    }

    private var emptySection: some View {
        Section {
            SpiralEmptyState(symbol: .clockArrowTriangleheadCounterclockwiseRotate90,
                             title: context.viewState.emptyTitle,
                             message: context.viewState.emptySubtitle)
                .listRowBackground(Color.clear)
        }
    }

    /// G5: a row with an approval or a chat opens it.
    private func rowsSection(_ items: [AgentActivityListItem], now: Date) -> some View {
        Section {
            ForEach(items) { item in
                let label = ListRowLabel<CompoundIcon>.default(title: item.title,
                                                 description: Self.rowDescription(for: item, now: now),
                                                 icon: Self.icon(for: item))
                if item.approvalID != nil || item.roomID != nil {
                    ListRow(label: label,
                            details: .title(Self.outcomeLabel(for: item)),
                            kind: .navigationLink {
                                context.send(viewAction: .selectItem(id: item.id))
                            })
                } else {
                    ListRow(label: label,
                            details: .title(Self.outcomeLabel(for: item)),
                            kind: .label)
                }
            }
        }
    }

    /// Row's secondary line: `<reason> · <relative time> · <room>` — the
    /// reason only when this build knows its code, the room only when the
    /// row happened in one. Shared with the notifications hub.
    static func rowDescription(for item: AgentActivityListItem, now: Date = .now) -> String {
        var parts: [String] = []
        if let agentName = item.agentName {
            parts.append(agentName)
        }
        if let reason = item.reason {
            parts.append(reason)
        }
        parts.append(AgentRelativeTime.string(for: item.createdAt, now: now))
        if let roomName = item.roomName {
            parts.append(roomName)
        }
        return parts.joined(separator: " · ")
    }

    private func sentinelSection(_ state: LoadMoreState) -> some View {
        Section {
            switch state {
            case .idle:
                // Trigger pagination on appear. Hidden visually
                // by the tiny progress glyph — the user usually
                // sees the next batch resolve before noticing
                // they've reached the bottom.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(UntranslatedL10n.screenAgentActivityLoadMore)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
                .onAppear { context.send(viewAction: .loadMore) }
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(UntranslatedL10n.screenAgentActivityLoadMore)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            case .failed:
                Button {
                    context.send(viewAction: .loadMore)
                } label: {
                    HStack(spacing: 8) {
                        CompoundIcon(\.errorSolid, size: .small, relativeTo: .compound.bodyMD)
                            .foregroundStyle(.compound.iconCriticalPrimary)
                        Text(UntranslatedL10n.screenAgentActivityLoadMoreFailed)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .listRowBackground(Color.clear)
            case .exhausted:
                EmptyView()
            }
        }
    }

    private var errorSection: some View {
        AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentActivityLoadFailed) {
            context.send(viewAction: .retry)
        }
    }

    // MARK: - Helpers

    /// Localised outcome word for the row's trailing details title
    /// (canon F5 — reuses the filter vocabulary, one wording source).
    static func outcomeLabel(for item: AgentActivityListItem) -> String {
        AgentActivityLabels.outcome(item.outcome)
    }

    /// Capability-keyed row icon; other capabilities fall back to the
    /// generic `history` glyph.
    static func icon(for item: AgentActivityListItem) -> KeyPath<CompoundIcons, Image> {
        switch item.capabilityName {
        case "messenger.reply_in_room", "messenger.reply_in_owner_dm": return \.chat
        case "messenger.dm_owner": return \.notifications
        default: return \.history
        }
    }

    /// Localised label for a filter case.
    static func filterLabel(_ filter: ActionOutcomeFilter) -> String {
        switch filter {
        case .all: return UntranslatedL10n.screenAgentActivityFilterAll
        case .pendingConsent: return UntranslatedL10n.screenAgentActivityFilterPendingConsent
        case .executed: return UntranslatedL10n.screenAgentActivityFilterExecuted
        case .failed: return UntranslatedL10n.screenAgentActivityFilterFailed
        case .declined: return UntranslatedL10n.screenAgentActivityFilterDeclined
        case .cancelled: return UntranslatedL10n.screenAgentActivityFilterCancelled
        case .denied: return UntranslatedL10n.screenAgentActivityFilterDenied
        case .ignored: return UntranslatedL10n.screenAgentActivityFilterIgnored
        }
    }
}

// MARK: - Previews

struct AgentActivityScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let loadingViewModel = makeViewModel(state: .loading)
    static let emptyViewModel = makeViewModel(state: .loaded([], loadMore: .exhausted))
    static let nothingPendingViewModel = makeViewModel(state: .loaded([], loadMore: .exhausted), filter: .pendingConsent)
    static let contentViewModel = makeViewModel(state: .loaded(sampleItems, loadMore: .exhausted))
    static let paginatingViewModel = makeViewModel(state: .loaded(sampleItems, loadMore: .idle(cursor: "preview-cursor")))
    static let errorViewModel = makeViewModel(state: .failed)

    static var previews: some View {
        ElementNavigationStack {
            AgentActivityScreen(context: loadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Loading")

        ElementNavigationStack {
            AgentActivityScreen(context: emptyViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(emptyViewModel))
        .previewDisplayName("Empty")

        ElementNavigationStack {
            AgentActivityScreen(context: nothingPendingViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(nothingPendingViewModel))
        .previewDisplayName("Nothing pending")

        ElementNavigationStack {
            AgentActivityScreen(context: contentViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(contentViewModel))
        .previewDisplayName("Content")

        ElementNavigationStack {
            AgentActivityScreen(context: paginatingViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(paginatingViewModel))
        .previewDisplayName("Paginating")

        ElementNavigationStack {
            AgentActivityScreen(context: errorViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(errorViewModel))
        .previewDisplayName("Error")
    }

    /// The rows are read on appear; the snapshot waits for the answer.
    private static func hasLoaded(_ viewModel: AgentActivityScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } }
    }

    /// The last row's capability, reason and outcome are newer than this
    /// build: "Other action", no reason, "Other". Each age sits 30 s into its
    /// unit, because `AgentRelativeTime.refreshSchedule`'s "now" lags up to 30 s.
    static let sampleEntries: [AgentActivityEntry] = [
        sampleEntry(id: "row-1", capabilityName: "messenger.reply_in_room", policyDecision: .allowedDirect,
                    policyReason: "relationship_approved", outcome: .executed, age: 150),
        sampleEntry(id: "row-2", capabilityName: "messenger.reply_in_room", policyDecision: .requiresOwnerConsent,
                    policyReason: "first_contact_with_unknown_visitor", outcome: .pending, age: 3630),
        sampleEntry(id: "row-3", capabilityName: "messenger.reply_in_room", policyDecision: .denied,
                    policyReason: "blocked_visitor", outcome: .denied, age: 86430),
        sampleEntry(id: "row-4", capabilityName: "future.capability", policyDecision: .ignored,
                    policyReason: "future_reason", outcome: .unknown(rawValue: "future"), age: 172_830)
    ]

    static let sampleItems = sampleEntries.map { AgentActivityScreenViewModel.mapItem($0, clientProxy: makeClientProxy()) }

    private static func sampleEntry(id: String,
                                    capabilityName: String,
                                    policyDecision: AgentActionPolicyDecision,
                                    policyReason: String,
                                    outcome: AgentActionOutcome,
                                    age: TimeInterval) -> AgentActivityEntry {
        AgentActivityEntry(id: id,
                           agentID: "preview-agent",
                           roomID: "!preview:spiral.md",
                           capabilityName: capabilityName,
                           inputRedacted: [:],
                           reasoningSummary: "pre-llm wake-gate skip (internal text, never shown)",
                           policyDecision: policyDecision,
                           policyReason: policyReason,
                           approvalID: nil,
                           longFlowID: nil,
                           outcome: outcome,
                           outcomeEventID: nil,
                           createdAt: Date(timeIntervalSinceNow: -age),
                           resolvedAt: nil)
    }

    private static func makeClientProxy() -> ClientProxyMock {
        let clientProxy = ClientProxyMock(.init())
        clientProxy.roomSummaryForIdentifierReturnValue = .mock(id: "!preview:spiral.md", name: "Book club")
        return clientProxy
    }

    static func makeViewModel(state: AgentActivityListState, filter: ActionOutcomeFilter = .all) -> AgentActivityScreenViewModel {
        let service = AgentPlatformServiceMock()
        switch state {
        case .loading:
            // Preview never resolves — stays in `.loading`.
            service.listAgentActivityAgentIDFilterCursorLimitClosure = { _, _, _, _ in
                try? await Task.sleep(for: .seconds(60))
                return .failure(.serverError(status: 0))
            }
        case .loaded(let items, let loadMore):
            let entries = items.isEmpty ? [] : sampleEntries
            let cursor: String? = if case .exhausted = loadMore { nil } else { "preview-cursor" }
            service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .success(.init(items: entries,
                                                                                          nextCursor: cursor))
        case .failed:
            service.listAgentActivityAgentIDFilterCursorLimitReturnValue = .failure(.serverError(status: 500))
        }
        return AgentActivityScreenViewModel(agentID: "preview-agent",
                                            initialFilter: filter,
                                            store: AgentsStore(service: service),
                                            clientProxy: makeClientProxy())
    }
}
