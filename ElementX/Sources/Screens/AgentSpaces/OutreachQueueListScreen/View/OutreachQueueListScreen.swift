//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

// AGENT-PLATFORM: Agent platform feature.
// The Spiral feature is built on Element's `TemplateScreen.swift`.
//
// Owner-facing queue inspector for one outreach agent. Each
// row carries a status badge (Queued / Pending approval / Sent
// / Blocked / Content blocked / Error) + the target MXID + an
// inline error message for the `.error` arm. Toolbar carries
// a "+" button that pushes `OutreachQueueAddScreen`.
//
// The status filter lives in a toolbar Picker (not segmented
// tabs) because (a) we have 6 statuses + the "All" sentinel,
// which would chew screen real-estate; (b) the picker matches
// the AgentActivityScreen filter pattern shipped in S170,
// keeping muscle memory consistent.

import Compound
import SpiralComponents
import SwiftUI

struct OutreachQueueListScreen: View {
    @Bindable var context: OutreachQueueListScreenViewModel.Context
    /// Pinned in snapshots (`EnvironmentValues.relativeTimeAnchor`); the clock otherwise.
    @Environment(\.relativeTimeAnchor) private var timeAnchor

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                skeletonSection
            case .loaded(let items) where items.isEmpty:
                emptySection
            case .loaded(let items):
                rowsSection(items)
            case .unavailable:
                unavailableSection
            case .failed:
                failedSection
            }
        }
        .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards and plain grey glyphs (decision 337).
        .navigationTitle(UntranslatedL10n.screenOutreachQueueTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .toolbar { toolbar }
    }

    // MARK: - Sections

    // Decision 330: the queue's rows as placeholders, after a short delay.
    private var skeletonSection: some View {
        Section {
            ListRow(kind: .custom {
                SpiralPreloader(label: L10n.commonLoading) {
                    SpiralPlaceholderRows(count: 4)
                }
            })
        }
    }

    private var emptySection: some View {
        Section {
            if context.viewState.isFiltering {
                SpiralEmptyState(symbol: .line3HorizontalDecrease,
                                 title: UntranslatedL10n.screenOutreachQueueEmptyFilteredTitle,
                                 message: UntranslatedL10n.screenOutreachQueueEmptyFilteredSubtitle)
                    .listRowBackground(Color.clear)
            } else {
                SpiralEmptyState(symbol: .paperplane,
                                 title: UntranslatedL10n.screenOutreachQueueEmptyTitle,
                                 message: UntranslatedL10n.screenOutreachQueueEmptySubtitle)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func rowsSection(_ items: [OutreachQueueEntry]) -> some View {
        Section {
            ForEach(items) { entry in
                queueRow(entry)
            }
        } header: {
            Text(UntranslatedL10n.screenOutreachQueueSectionTitle)
                .compoundListSectionHeader()
        }
    }

    private func queueRow(_ entry: OutreachQueueEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.targetMXID)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Spacer()
                statusBadge(for: entry.status)
            }

            if let body = entry.draftBody, !body.isEmpty {
                Text(body)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(3)
            }

            if let err = entry.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textCriticalPrimary)
            }

            createdAtText(entry.createdAt)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
        }
        .padding(.vertical, 4)
    }

    /// How long ago an entry was made: a live count in the app, and against the pinned instant in snapshots, where a
    /// count that moves with the clock read «30 min, 1 sec» one run and «30 min, 0 secs» the next. The pinned count
    /// leaves out zero units («1 hr», where the app shows «1 hr, 0 min»).
    private func createdAtText(_ date: Date) -> Text {
        if let timeAnchor {
            Text(date..<max(date, timeAnchor), format: .components(style: .abbreviated, fields: [.day, .hour, .minute, .second]))
        } else {
            Text(date, style: .relative)
        }
    }

    /// Compact status pill: short label, foreground colour
    /// per status semantic. Keeps the row chrome cheap so
    /// 100 rows scroll smoothly.
    // Canon F5: the shared semantic-token chip.
    private func statusBadge(for status: OutreachTargetStatus) -> some View {
        let (label, variant) = Self.badgeStyle(for: status)
        return AgentStatusBadge(title: label, variant: variant)
    }

    static func badgeStyle(for status: OutreachTargetStatus) -> (String, AgentStatusBadge.Variant) {
        switch status {
        case .queued:
            return (UntranslatedL10n.screenOutreachQueueStatusQueued, .accent)
        case .pendingApproval:
            return (UntranslatedL10n.screenOutreachQueueStatusPendingApproval, .accent)
        case .sent:
            return (UntranslatedL10n.screenOutreachQueueStatusSent, .success)
        case .blockedByTarget:
            return (UntranslatedL10n.screenOutreachQueueStatusBlockedByTarget, .critical)
        case .contentBlocked:
            return (UntranslatedL10n.screenOutreachQueueStatusContentBlocked, .critical)
        case .error:
            return (UntranslatedL10n.screenOutreachQueueStatusError, .critical)
        case .unknown(let raw):
            return (raw, .neutral)
        }
    }

    private var unavailableSection: some View {
        Section {
            SpiralEmptyState(symbol: .paperplane,
                             title: UntranslatedL10n.screenOutreachQueueUnavailableTitle,
                             message: UntranslatedL10n.screenOutreachQueueUnavailableSubtitle)
                .listRowBackground(Color.clear)
        }
    }

    private var failedSection: some View {
        AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenOutreachQueueLoadFailed) {
            context.send(viewAction: .retry)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    // Canon §7: filters are a Picker inside a Menu with a CompoundIcon
    // label; the add button uses the Compound plus (F4 fix — was SF
    // symbols with a hand-checked selection hack).
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker(UntranslatedL10n.screenOutreachQueueFilterMenuTitle,
                       selection: Binding(get: { context.viewState.statusFilter },
                                          set: { context.send(viewAction: .selectFilter($0)) })) {
                    Text(UntranslatedL10n.screenOutreachQueueFilterAll)
                        .tag(OutreachTargetStatus?.none)
                    ForEach(OutreachTargetStatus.allCases, id: \.wireValue) { status in
                        Text(Self.badgeStyle(for: status).0)
                            .tag(OutreachTargetStatus?.some(status))
                    }
                }
            } label: {
                CompoundIcon(\.filter, size: .small, relativeTo: .compound.bodyLG)
                    .foregroundStyle(.compound.iconPrimary)
            }
            .accessibilityLabel(UntranslatedL10n.screenOutreachQueueFilterMenuTitle)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                context.send(viewAction: .openAddTargets)
            } label: {
                CompoundIcon(\.plus)
                    .accessibilityHidden(true)
            }
            .accessibilityLabel(UntranslatedL10n.screenOutreachQueueActionAddTargets)
        }
    }
}

// MARK: - Previews

struct OutreachQueueListScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let sample: [OutreachQueueEntry] = [
        OutreachQueueEntry(id: "row-1",
                           targetMXID: "@bob:spiral.md",
                           status: .queued,
                           approvalID: nil,
                           draftBody: nil,
                           errorMessage: nil,
                           createdAt: PreviewClock.now.addingTimeInterval(-3600),
                           updatedAt: PreviewClock.now.addingTimeInterval(-3600)),
        OutreachQueueEntry(id: "row-2",
                           targetMXID: "@carol:spiral.md",
                           status: .pendingApproval,
                           approvalID: "approval-1",
                           draftBody: "Hi Carol! I'm reaching out from Acme Sales — saw your recent post about widget supply…",
                           errorMessage: nil,
                           createdAt: PreviewClock.now.addingTimeInterval(-7200),
                           updatedAt: PreviewClock.now.addingTimeInterval(-300)),
        OutreachQueueEntry(id: "row-3",
                           targetMXID: "@dave:spiral.md",
                           status: .sent,
                           approvalID: "approval-2",
                           draftBody: "Hi Dave! Following up on yesterday's chat…",
                           errorMessage: nil,
                           createdAt: PreviewClock.now.addingTimeInterval(-86400),
                           updatedAt: PreviewClock.now.addingTimeInterval(-43200)),
        OutreachQueueEntry(id: "row-4",
                           targetMXID: "@eve:spiral.md",
                           status: .error,
                           approvalID: nil,
                           draftBody: nil,
                           errorMessage: "LLM 503 — retry scheduled",
                           createdAt: PreviewClock.now.addingTimeInterval(-1800),
                           updatedAt: PreviewClock.now.addingTimeInterval(-1800))
    ]

    // Held here: the screen's context does not keep its view model alive, and the snapshot waits on it.
    static let loadingViewModel = makeViewModel(state: .loading)
    static let loadedViewModel = makeViewModel(state: .loaded(sample))
    static let emptyViewModel = makeViewModel(state: .loaded([]))
    static let emptyFilteredViewModel = makeViewModel(state: .loaded([]), filter: .queued)
    static let unavailableViewModel = makeViewModel(state: .unavailable(reason: "agent behaviour is not Outreach"))
    static let failedViewModel = makeViewModel(state: .failed(reason: "transport error"))

    static var previews: some View {
        ElementNavigationStack { screen(loadingViewModel, waitsForLoading: true) }
            .environment(\.spiralPreloaderDelay, .zero)
            .previewDisplayName("Loading")

        ElementNavigationStack { screen(loadedViewModel) }
            .previewDisplayName("Loaded — mixed")

        ElementNavigationStack { screen(emptyViewModel) }
            .previewDisplayName("Empty — no filter")

        ElementNavigationStack { screen(emptyFilteredViewModel) }
            .previewDisplayName("Empty — filtered")

        ElementNavigationStack { screen(unavailableViewModel) }
            .previewDisplayName("Unavailable (409)")

        ElementNavigationStack { screen(failedViewModel) }
            .previewDisplayName("Failed")
    }

    /// The snapshot waits for the store's read, except while loading.
    static func screen(_ viewModel: OutreachQueueListScreenViewModel, waitsForLoading: Bool = false) -> some View {
        OutreachQueueListScreen(context: viewModel.context)
            .snapshotPreferences(expect: viewModel.context.observe(\.viewState.listState).map {
                if case .loading = $0 { waitsForLoading } else { !waitsForLoading }
            })
    }

    /// The store reads what `state` names.
    static func makeViewModel(state: OutreachQueueListState, filter: OutreachTargetStatus? = nil) -> OutreachQueueListScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitClosure = { _, _, _ in
            switch state {
            case .loading:
                try? await Task.sleep(for: .seconds(60))
                return .failure(.serverError(status: 0))
            case .loaded(let entries):
                return .success(entries)
            case .unavailable(let reason):
                return .failure(.conflict(detail: reason))
            case .failed:
                return .failure(.serverError(status: 500))
            }
        }
        return OutreachQueueListScreenViewModel(agentID: "preview-agent",
                                                store: AgentsStore(service: service),
                                                initialFilter: filter)
    }
}
