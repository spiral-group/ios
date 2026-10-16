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
import SwiftUI

struct OutreachQueueListScreen: View {
    @Bindable var context: OutreachQueueListScreenViewModel.Context

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
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenOutreachQueueTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .refreshable { context.send(viewAction: .refresh) }
        .onAppear { context.send(viewAction: .appeared) }
        .toolbar { toolbar }
    }

    // MARK: - Sections

    // Canon §3 (operator ruling, CODEBASE/14): fast/rare data → a delayed
    // spinner, never a skeleton (it only flickers).
    private var skeletonSection: some View {
        Section {
            ListRow(kind: .custom {
                DelayedProgressView()
                    .frame(minHeight: 80)
            })
        }
        .listRowBackground(Color.clear)
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 12) {
                BigIcon(icon: \.send)
                Text(context.viewState.isFiltering
                    ? UntranslatedL10n.screenOutreachQueueEmptyFilteredTitle
                    : UntranslatedL10n.screenOutreachQueueEmptyTitle)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(context.viewState.isFiltering
                    ? UntranslatedL10n.screenOutreachQueueEmptyFilteredSubtitle
                    : UntranslatedL10n.screenOutreachQueueEmptySubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
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

            Text(entry.createdAt, style: .relative)
                .font(.compound.bodyXS)
                .foregroundStyle(.compound.textSecondary)
        }
        .padding(.vertical, 4)
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
            VStack(spacing: 16) {
                BigIcon(icon: \.send, style: .alertSolid)
                Text(UntranslatedL10n.screenOutreachQueueUnavailableTitle)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(UntranslatedL10n.screenOutreachQueueUnavailableSubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
        }
    }

    private var failedSection: some View {
        AgentSpacesRetryErrorSection {
            context.send(viewAction: .refresh)
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

struct OutreachQueueListScreen_Previews: PreviewProvider, TestablePreview {
    static let sample: [OutreachQueueEntry] = [
        OutreachQueueEntry(id: "row-1",
                           targetMXID: "@bob:spiral.md",
                           status: .queued,
                           approvalID: nil,
                           draftBody: nil,
                           errorMessage: nil,
                           createdAt: Date().addingTimeInterval(-3600),
                           updatedAt: Date().addingTimeInterval(-3600)),
        OutreachQueueEntry(id: "row-2",
                           targetMXID: "@carol:spiral.md",
                           status: .pendingApproval,
                           approvalID: "approval-1",
                           draftBody: "Hi Carol! I'm reaching out from Acme Sales — saw your recent post about widget supply…",
                           errorMessage: nil,
                           createdAt: Date().addingTimeInterval(-7200),
                           updatedAt: Date().addingTimeInterval(-300)),
        OutreachQueueEntry(id: "row-3",
                           targetMXID: "@dave:spiral.md",
                           status: .sent,
                           approvalID: "approval-2",
                           draftBody: "Hi Dave! Following up on yesterday's chat…",
                           errorMessage: nil,
                           createdAt: Date().addingTimeInterval(-86400),
                           updatedAt: Date().addingTimeInterval(-43200)),
        OutreachQueueEntry(id: "row-4",
                           targetMXID: "@eve:spiral.md",
                           status: .error,
                           approvalID: nil,
                           draftBody: nil,
                           errorMessage: "LLM 503 — retry scheduled",
                           createdAt: Date().addingTimeInterval(-1800),
                           updatedAt: Date().addingTimeInterval(-1800))
    ]

    static var previews: some View {
        ElementNavigationStack { screen(state: .loading) }
            .previewDisplayName("Loading")

        ElementNavigationStack { screen(state: .loaded(sample)) }
            .previewDisplayName("Loaded — mixed")

        ElementNavigationStack { screen(state: .loaded([])) }
            .previewDisplayName("Empty — no filter")

        ElementNavigationStack { screen(state: .loaded([]), filter: .queued) }
            .previewDisplayName("Empty — filtered")

        ElementNavigationStack { screen(state: .unavailable(reason: "agent behaviour is not Outreach")) }
            .previewDisplayName("Unavailable (409)")

        ElementNavigationStack { screen(state: .failed(reason: "transport error")) }
            .previewDisplayName("Failed")
    }

    static func screen(state: OutreachQueueListState, filter: OutreachTargetStatus? = nil) -> some View {
        let service = AgentPlatformServiceMock()
        service.listOutreachQueueAgentIDStatusLimitClosure = { _, _, _ in
            try? await Task.sleep(for: .seconds(60))
            return .failure(.serverError(status: 0))
        }
        let viewModel = OutreachQueueListScreenViewModel(agentID: "preview-agent",
                                                         agentPlatformService: service,
                                                         initialState: state,
                                                         initialFilter: filter)
        return OutreachQueueListScreen(context: viewModel.context)
    }
}
