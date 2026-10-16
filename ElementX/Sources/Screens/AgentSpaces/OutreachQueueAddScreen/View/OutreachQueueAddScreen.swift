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
// Editor + result summary in one screen. Three phases:
//
//   * `.draft`     — textarea + line counter + Save button.
//   * `.submitting`— textarea disabled; progress overlay.
//   * `.results`   — per-row outcome table + summary chips
//                   (Queued / Duplicate / Invalid) + Done.

import Compound
import SwiftUI

struct OutreachQueueAddScreen: View {
    @Bindable var context: OutreachQueueAddScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.detailState {
            case .draft, .submitting, .failed:
                editorSection
            case .results(let result):
                summarySection(result)
                resultRowsSection(result.items)
            case .unavailable:
                unavailableSection
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenOutreachQueueAddTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(item: $context.alertInfo)
        .toolbar { toolbar }
    }

    // MARK: - Editor

    private var editorSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenOutreachQueueAddFieldPlaceholder),
                    kind: .textField(text: $context.draftText, axis: .vertical))
                .lineLimit(8...20)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .accessibilityIdentifier("outreachQueueAddField")
                .disabled(context.viewState.detailState.isInFlight)
        } header: {
            Text(UntranslatedL10n.screenOutreachQueueAddSectionTitle)
                .compoundListSectionHeader()
        } footer: {
            HStack(spacing: 8) {
                Text(UntranslatedL10n.screenOutreachQueueAddSectionFooter)
                Spacer()
                Text("\(context.viewState.parsedCount) / \(OutreachQueueAddScreenViewState.maxBatchSize)")
                    .monospacedDigit()
                    .foregroundStyle(context.viewState.isOverLimit ? .compound.textCriticalPrimary : .compound.textSecondary)
            }
            .compoundListSectionFooter()
        }
    }

    // MARK: - Results

    private func summarySection(_ result: EnqueueOutreachResult) -> some View {
        Section {
            HStack(spacing: 12) {
                AgentStatusBadge(title: UntranslatedL10n.screenOutreachQueueAddSummaryAccepted(result.accepted),
                                 variant: .success)
                AgentStatusBadge(title: UntranslatedL10n.screenOutreachQueueAddSummaryRejected(result.rejected),
                                 variant: result.rejected > 0 ? .critical : .neutral)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private func resultRowsSection(_ items: [EnqueueOutreachItem]) -> some View {
        Section {
            ForEach(items) { item in
                resultRow(item)
            }
        } header: {
            Text(UntranslatedL10n.screenOutreachQueueAddResultsSectionTitle)
                .compoundListSectionHeader()
        }
    }

    private func resultRow(_ item: EnqueueOutreachItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.targetMXID)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
                Spacer()
                outcomeBadge(for: item.outcome)
            }
            if case .invalid(let reason) = item.outcome {
                Text(reason)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textCriticalPrimary)
            }
        }
        .padding(.vertical, 4)
    }

    // Canon F5: the shared semantic-token chip.
    private func outcomeBadge(for outcome: EnqueueOutreachOutcome) -> some View {
        let (label, variant) = Self.outcomeStyle(for: outcome)
        return AgentStatusBadge(title: label, variant: variant)
    }

    static func outcomeStyle(for outcome: EnqueueOutreachOutcome) -> (String, AgentStatusBadge.Variant) {
        switch outcome {
        case .queued:
            return (UntranslatedL10n.screenOutreachQueueAddOutcomeQueued, .success)
        case .duplicate:
            return (UntranslatedL10n.screenOutreachQueueAddOutcomeDuplicate, .neutral)
        case .invalid:
            return (UntranslatedL10n.screenOutreachQueueAddOutcomeInvalid, .critical)
        }
    }

    // MARK: - Unavailable

    private var unavailableSection: some View {
        Section {
            VStack(spacing: 16) {
                BigIcon(icon: \.send, style: .alertSolid)
                Text(UntranslatedL10n.screenOutreachQueueAddUnavailableTitle)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(UntranslatedL10n.screenOutreachQueueAddUnavailableSubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if context.viewState.detailState.isTerminalAfterSubmit {
                Button(L10n.actionDone) { context.send(viewAction: .dismiss) }
            } else {
                Button(L10n.actionCancel) { context.send(viewAction: .cancel) }
                    .disabled(context.viewState.detailState.isInFlight)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if !context.viewState.detailState.isTerminalAfterSubmit {
                Button(L10n.actionSave) { context.send(viewAction: .submit) }
                    .disabled(!canSave)
            }
        }
    }

    private var canSave: Bool {
        if context.viewState.detailState.isInFlight { return false }
        if context.viewState.isOverLimit { return false }
        return context.viewState.parsedCount > 0
    }
}

// MARK: - Previews

struct OutreachQueueAddScreen_Previews: PreviewProvider, TestablePreview {
    static let sampleResult = EnqueueOutreachResult(items: [
        EnqueueOutreachItem(targetMXID: "@bob:spiral.md",
                            outcome: .queued(id: "target-1")),
        EnqueueOutreachItem(targetMXID: "@carol:spiral.md",
                            outcome: .queued(id: "target-2")),
        EnqueueOutreachItem(targetMXID: "@dave:spiral.md",
                            outcome: .duplicate),
        EnqueueOutreachItem(targetMXID: "not-an-mxid",
                            outcome: .invalid(reason: "expected `@user:server`"))
    ],
    accepted: 2,
    rejected: 2)

    static var previews: some View {
        ElementNavigationStack { screen(state: .draft, text: "") }
            .previewDisplayName("Draft — empty")

        ElementNavigationStack { screen(state: .draft, text: "@bob:spiral.md\n@carol:spiral.md") }
            .previewDisplayName("Draft — two MXIDs")

        ElementNavigationStack { screen(state: .submitting, text: "@bob:spiral.md") }
            .previewDisplayName("Submitting")

        ElementNavigationStack { screen(state: .results(sampleResult), text: "") }
            .previewDisplayName("Results — mixed outcomes")

        ElementNavigationStack { screen(state: .unavailable(reason: "agent is not Outreach"), text: "") }
            .previewDisplayName("Unavailable (409)")

        ElementNavigationStack { screen(state: .failed(reason: "transport error"), text: "@bob:spiral.md") }
            .previewDisplayName("Failed — keeps buffer")
    }

    static func screen(state: OutreachQueueAddState, text: String) -> some View {
        let service = AgentPlatformServiceMock()
        service.enqueueOutreachTargetsAgentIDMxidsClosure = { _, _ in
            try? await Task.sleep(for: .seconds(60))
            return .failure(.serverError(status: 0))
        }
        let viewModel = OutreachQueueAddScreenViewModel(agentID: "preview-agent",
                                                        agentPlatformService: service,
                                                        initialState: state,
                                                        initialText: text)
        return OutreachQueueAddScreen(context: viewModel.context)
    }
}
