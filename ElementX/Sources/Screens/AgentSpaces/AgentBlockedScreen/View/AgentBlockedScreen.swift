//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SwiftUI

/// The people one agent blocks (decision 194), newest first, each with «Разблокировать».
struct AgentBlockedScreen: View {
    @Bindable var context: AgentBlockedScreenViewModel.Context

    var body: some View {
        Form {
            switch context.viewState.listState {
            case .loading:
                Section {
                    ListRow(kind: .custom {
                        SpiralPreloader(label: L10n.commonLoading) {
                            SpiralPlaceholderRows(count: 3)
                        }
                    })
                }
            case .failed:
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentBlockedLoadFailure) {
                    context.send(viewAction: .retry)
                }
            case .loaded(let blocks, _) where blocks.isEmpty:
                emptySection
            case .loaded(let blocks, _):
                blocksSection(blocks)
                if let sentinel = context.viewState.sentinel {
                    sentinelSection(sentinel)
                }
            }
        }
        .compoundList()
        .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
        .navigationTitle(UntranslatedL10n.screenAgentDetailBlocked)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .alert(item: $context.alertInfo)
    }

    private func blocksSection(_ blocks: [AgentBlockedContact]) -> some View {
        Section {
            ForEach(blocks) { block in
                ListRow(kind: .custom {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(block.name)
                                .font(.compound.bodyLG)
                                .foregroundStyle(.compound.textPrimary)
                                .lineLimit(1)
                            if block.displayName != nil {
                                Text(block.contactMXID)
                                    .font(.compound.bodySM)
                                    .foregroundStyle(.compound.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if context.viewState.unblockingMXID == block.contactMXID {
                            ProgressView()
                        } else {
                            Button(UntranslatedL10n.screenRoomMemberDetailsAgentUnblockAction) {
                                context.send(viewAction: .unblock(contactMXID: block.contactMXID))
                            }
                            .buttonStyle(.compound(.secondary, size: .small))
                            .disabled(context.viewState.unblockingMXID != nil)
                        }
                    }
                    .padding(.horizontal, ListRowPadding.horizontal)
                    .padding(.vertical, ListRowPadding.vertical)
                })
            }
        } footer: {
            Text(UntranslatedL10n.screenAgentBlockedFooter)
                .compoundListSectionFooter()
        }
    }

    private var emptySection: some View {
        Section {
            SpiralEmptyState(symbol: .nosign,
                             title: UntranslatedL10n.screenAgentBlockedEmpty,
                             message: UntranslatedL10n.screenAgentBlockedFooter)
                .listRowBackground(Color.clear)
        }
    }

    private func sentinelSection(_ state: LoadMoreState) -> some View {
        Section {
            switch state {
            case .failed:
                ListRow(label: .plain(title: UntranslatedL10n.screenAgentActivityLoadMoreFailed),
                        kind: .button { context.send(viewAction: .loadMore) })
            default:
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
            }
        }
    }
}

// MARK: - Previews

struct AgentBlockedScreen_Previews: PreviewProvider, TestablePreview {
    static let listViewModel = makeViewModel(.success(.init(blocks: [.init(contactMXID: "@bob:spiral.md", displayName: "Bob", blockedAt: .now),
                                                                     .init(contactMXID: "@spam-4211:example.org", displayName: nil, blockedAt: .now)],
                                                            nextCursor: nil)))
    static let emptyViewModel = makeViewModel(.success(.init(blocks: [], nextCursor: nil)))
    static let failedViewModel = makeViewModel(.failure(.serverError(status: 500)))

    static var previews: some View {
        preview(listViewModel, name: "List")
        preview(emptyViewModel, name: "Empty")
        preview(failedViewModel, name: "Failed")
    }

    private static func preview(_ viewModel: AgentBlockedScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            AgentBlockedScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.listState).map { if case .loading = $0 { false } else { true } })
        .previewDisplayName(name)
    }

    static func makeViewModel(_ result: Result<AgentBlockedContactsPage, AgentPlatformError>) -> AgentBlockedScreenViewModel {
        let service = AgentPlatformServiceMock()
        service.listBlockedContactsAgentIDCursorLimitReturnValue = result
        return AgentBlockedScreenViewModel(agent: AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                                      displayName: "Anna's assistant", avatarMXC: nil, kind: "personal_assistant",
                                                                      visibility: "public", lifecycleState: "active", roomCount: 1, activeToolCount: 0),
                                           agentPlatformService: service,
                                           store: AgentsStore(service: service),
                                           userIndicatorController: UserIndicatorControllerMock())
    }
}
