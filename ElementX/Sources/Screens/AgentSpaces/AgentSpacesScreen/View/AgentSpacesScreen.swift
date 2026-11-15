//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

/// The Agents tab root (step B, decision 191): one list, a section per space
/// — «Личное» first, then each company with «Изменить» in its header — and
/// the agents straight inside it. A Solo user sees their assistant at once.
/// With `SpiralFeatures.companySpaces` off (396) it is the assistant alone:
/// no space headers, no company and no «+».
struct AgentSpacesScreen: View {
    @Bindable var context: AgentSpacesScreenViewModel.Context

    var body: some View {
        mainContent
            .navigationTitle(UntranslatedL10n.screenAgentSpacesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            // Brief 0083 (decision 308 #6): no bloom behind the bar on the reviewer's path, as on Chats.
            .feedSyncStatus(context.viewState.syncStatus) // AGENT-PLATFORM: platform sync (decision 289)
            .onAppear { context.send(viewAction: .appeared) }
            .onDisappear { context.send(viewAction: .disappeared) }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch context.viewState.listState {
        case .loading:
            // Decision 330: the agents' rows as placeholders, after a short delay.
            Form {
                Section {
                    ListRow(kind: .custom {
                        SpiralPreloader(label: L10n.commonLoading) {
                            SpiralPlaceholderRows(count: 3, leading: .avatar(SpiralAvatarSize.medium))
                        }
                    })
                }
            }
            .spiralGroupedList() // Brief 0083 (P4-D): iOS's grouped cards, as Settings (decision 337).
        case .provisioning:
            provisioningState
        case .failure:
            failureState
        case .loaded(let sections):
            Form {
                if context.viewState.hasNoSpaces {
                    Section { assistantPendingRow }
                }
                ForEach(sections) { section in
                    spaceSection(section)
                }
            }
            .spiralGroupedList()
            // S5: rows that changed while covered are made anew as the list shows again.
            .id(context.viewState.listGeneration)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func spaceSection(_ section: AgentSpaceSection) -> some View {
        if SpiralFeatures.companySpaces {
            Section {
                spaceRows(section)
            } header: {
                sectionHeader(section)
            }
        } else {
            // The Personal space alone needs no name above it.
            Section {
                spaceRows(section)
            }
        }
    }

    @ViewBuilder
    private func spaceRows(_ section: AgentSpaceSection) -> some View {
        switch section.content {
        case .failed:
            ListRow(label: .default(title: UntranslatedL10n.screenAgentSpaceErrorTitle,
                                    description: UntranslatedL10n.screenAgentSpacesSectionRetry,
                                    icon: \.error,
                                    role: .error),
                    kind: .button {
                        context.send(viewAction: .retry)
                    })
                    .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.error)
        case .loaded:
            ForEach(section.agents) { agent in
                agentRow(agent)
            }

            if section.isAssistantPending {
                assistantPendingRow
            }

            if SpiralFeatures.companySpaces, section.summary.kind == .company, section.agents.isEmpty {
                ListRow(label: .action(title: UntranslatedL10n.screenCreateAgentTitle, icon: \.plus),
                        kind: .button {
                            context.send(viewAction: .createAgent(orgID: section.id))
                        })
                        .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.newAgent(section.id))
            }
        }
    }

    private func sectionHeader(_ section: AgentSpaceSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.summary.displayName)
                .compoundListSectionHeader()
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.space(section.id))

            Spacer()

            // The Personal space is named by the app and never renamed (B6).
            if section.summary.kind == .company, section.detail != nil {
                Button(UntranslatedL10n.screenAgentsActionEdit) {
                    context.send(viewAction: .editCompany(orgID: section.id))
                }
                .font(.compound.bodySMSemibold)
                .foregroundStyle(.compound.textActionAccent)
                .textCase(nil)
                .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.editCompany(section.id))
            }
        }
    }

    /// Never a blank list: the assistant is on its way, and a tap reads again. Brief 0083 (P4-D, critique F5): the
    /// assistant's card with a spinner where its avatar will be, not the Agents tab's glyph.
    private var assistantPendingRow: some View {
        ListRow(kind: .custom {
            Button {
                context.send(viewAction: .retry)
            } label: {
                SpiralAgentCard(name: UntranslatedL10n.screenAgentSpacesAssistantPending,
                                details: UntranslatedL10n.screenAgentSpacesSectionRetry) {
                    ProgressView()
                        .frame(width: SpiralAvatarSize.medium, height: SpiralAvatarSize.medium)
                        .background(Color.compound.bgSubtleSecondary, in: .circle)
                } accessory: {
                    EmptyView()
                }
            }
        })
    }

    /// Brief 0083 (P4-D): Spiral's agent card: the avatar, the name, what it is, its status and, when no role says
    /// what it does, its chats and tools.
    private func agentRow(_ agent: AgentSpaceAgentCard) -> some View {
        AgentRow(title: agent.displayName,
                 role: agent.roleLine,
                 presence: agent.presence(),
                 description: agent.rowFacts,
                 avatarContentID: agent.matrixUserID,
                 avatarURL: agent.avatarMXC.flatMap(URL.init(string:)),
                 avatarSize: SpiralAvatarSize.medium,
                 mediaProvider: context.mediaProvider,
                 kind: .navigate) {
            context.send(viewAction: .selectAgent(agentID: agent.agentID))
        }
        .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.agent(agent.matrixUserID))
    }

    // MARK: States

    /// Brief 0083 (P4-D): the process in words with a spinner; Element's icon tile and the Agents tab's glyph are gone.
    private var provisioningState: some View {
        VStack(spacing: CompoundDesignTokens.space4X) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: CompoundDesignTokens.space2X) {
                Text(UntranslatedL10n.screenAgentSpacesProvisioningTitle)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(UntranslatedL10n.screenAgentSpacesProvisioningSubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, CompoundDesignTokens.space6X)
        .centredInScrollView()
    }

    private var failureState: some View {
        Form {
            AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentSpacesErrorTitle) {
                context.send(viewAction: .retry)
            }
        }
        .spiralGroupedList()
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // The notifications hub with the pending badge.
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                context.send(viewAction: .showNotifications)
            } label: {
                CompoundIcon(\.notifications)
                    .accessibilityHidden(true)
                    .overlay(alignment: .topTrailing) {
                        if context.viewState.pendingApprovalsCount > 0 {
                            Text("\(context.viewState.pendingApprovalsCount)")
                                .font(.compound.bodyXS)
                                .foregroundStyle(.compound.textOnSolidPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.compound.bgCriticalPrimary))
                                .offset(x: 8, y: -6)
                        }
                    }
            }
            .accessibilityLabel(UntranslatedL10n.screenNotificationsHubTitle)
            .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.approvalsBell) // AGENT-PLATFORM (decision 148)
        }

        // Last, as the Feed's compose is (decision 349). It only makes companies and their agents (396).
        if SpiralFeatures.companySpaces {
            ToolbarItem(placement: .navigationBarTrailing) {
                addMenu
            }
        }
    }

    /// «+»: «Новый агент» (a role agent lives in a company, so one per
    /// company when there are several) and «Новая компания».
    private var addMenu: some View {
        Menu {
            let companies = context.viewState.companies
            if companies.count == 1, let company = companies.first {
                Button {
                    context.send(viewAction: .createAgent(orgID: company.orgID))
                } label: {
                    Label(UntranslatedL10n.screenCreateAgentTitle, icon: \.userAdd)
                }
            } else if companies.count > 1 {
                Menu {
                    ForEach(companies) { company in
                        Button(company.displayName) {
                            context.send(viewAction: .createAgent(orgID: company.orgID))
                        }
                    }
                } label: {
                    Label(UntranslatedL10n.screenCreateAgentTitle, icon: \.userAdd)
                }
            }

            Button {
                context.send(viewAction: .createCompany)
            } label: {
                Label(UntranslatedL10n.screenCreateCompanyTitle, icon: \.company)
            }
            .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.newCompany)
        } label: {
            CompoundIcon(\.plus)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(L10n.actionCreate)
        .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.addMenu)
    }
}

// MARK: - Previews

struct AgentSpacesScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    static let failedSpaceViewModel = makeViewModel(personalReadFails: true)
    static let pendingAssistantViewModel = makeViewModel(personalAgents: false)
    static let noSpacesViewModel = makeViewModel(hasSpaces: false)

    static var previews: some View {
        // The directory is read on appear; the snapshot waits for the answer.
        ElementNavigationStack {
            AgentSpacesScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(viewModel))

        ElementNavigationStack {
            AgentSpacesScreen(context: failedSpaceViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(failedSpaceViewModel))
        .previewDisplayName("Space read failed")

        ElementNavigationStack {
            AgentSpacesScreen(context: pendingAssistantViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(pendingAssistantViewModel))
        .previewDisplayName("Assistant not there yet")

        ElementNavigationStack {
            AgentSpacesScreen(context: noSpacesViewModel.context)
        }
        .snapshotPreferences(expect: hasLoaded(noSpacesViewModel))
        .previewDisplayName("No spaces yet")
    }

    private static func hasLoaded(_ viewModel: AgentSpacesScreenViewModel) -> some AsyncSequence<Bool, Never> {
        viewModel.context.observe(\.viewState.listState).map { if case .loaded = $0 { true } else { false } }
    }

    /// The directory lists a company too, as an older account's does: with `SpiralFeatures.companySpaces` off it
    /// isn't shown (396).
    static func makeViewModel(personalReadFails: Bool = false, personalAgents: Bool = true, hasSpaces: Bool = true) -> AgentSpacesScreenViewModel {
        let personal = AgentSpaceSummary(orgID: "org-personal", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1)
        let acme = AgentSpaceSummary(orgID: "org-acme", name: "Acme Corp", kind: .company, avatarMXC: nil, agentCount: 1)

        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: hasSpaces ? [personal, acme] : [], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            switch orgID {
            case personal.orgID where personalReadFails:
                return .failure(.serverError(status: 500))
            case personal.orgID where !personalAgents:
                return .success(.init(orgID: orgID, name: personal.name, kind: .solo, avatarMXC: nil, industry: nil, website: nil, agents: []))
            case personal.orgID:
                return .success(.init(orgID: orgID, name: personal.name, kind: .solo, avatarMXC: nil, industry: nil, website: nil,
                                      agents: [.init(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                     displayName: "Alex · assistant", avatarMXC: nil, kind: "personal_assistant",
                                                     visibility: "public", lifecycleState: "active", roomCount: 4, activeToolCount: 2)]))
            default:
                return .success(.init(orgID: orgID, name: acme.name, kind: .company, avatarMXC: nil, industry: "Logistics", website: "acme.com",
                                      agents: [.init(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md",
                                                     displayName: "Sales · Acme Corp", avatarMXC: nil, kind: "sales",
                                                     visibility: "public", lifecycleState: "active", roomCount: 2, activeToolCount: 1)]))
            }
        }

        return AgentSpacesScreenViewModel(userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@owner:spiral.md")))),
                                          store: AgentsStore(service: service))
    }
}
