//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The Agents tab root (step B, decision 191): one list, a section per space
/// — «Личное» first, then each company with «Изменить» in its header — and
/// the agents straight inside it. A Solo user sees their assistant at once.
struct AgentSpacesScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Bindable var context: AgentSpacesScreenViewModel.Context

    var body: some View {
        mainContent
            .navigationTitle(UntranslatedL10n.screenAgentSpacesTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            // AGENT-PLATFORM: navigation-bar bloom restored (ADR-0005 revision) — now
            // a blue glow via the synced alpha-blue subtle gradient (see HomeScreen).
            .toolbarBloom(hasSearchBar: false)
            .onAppear { context.send(viewAction: .appeared) } // AGENT-PLATFORM (coverage walk F4)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch context.viewState.listState {
        case .loading:
            // Fast, infrequent data → a delayed centred spinner (no
            // skeleton flicker). See CODEBASE/14 §3.
            DelayedProgressView()
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
            .compoundList()
            .refreshable { context.send(viewAction: .refresh) }
        }
    }

    // MARK: Sections

    private func spaceSection(_ section: AgentSpaceSection) -> some View {
        Section {
            switch section.content {
            case .failed:
                ListRow(label: .default(title: UntranslatedL10n.screenAgentSpaceErrorTitle,
                                        description: UntranslatedL10n.screenAgentSpacesSectionRetry,
                                        icon: \.error,
                                        role: .error),
                        kind: .button {
                            context.send(viewAction: .refresh)
                        })
                        .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.error)
            case .loaded:
                ForEach(section.agents) { agent in
                    agentRow(agent)
                }

                if section.isAssistantPending {
                    assistantPendingRow
                }

                if section.summary.kind == .company, section.agents.isEmpty {
                    ListRow(label: .action(title: UntranslatedL10n.screenCreateAgentTitle, icon: \.plus),
                            kind: .button {
                                context.send(viewAction: .createAgent(orgID: section.id))
                            })
                            .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.newAgent(section.id))
                }
            }
        } header: {
            sectionHeader(section)
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

    /// Never a blank list: the assistant is on its way, and a tap reads again.
    private var assistantPendingRow: some View {
        ListRow(label: .default(title: UntranslatedL10n.screenAgentSpacesAssistantPending,
                                description: UntranslatedL10n.screenAgentSpacesSectionRetry,
                                icon: \.host),
                kind: .button {
                    context.send(viewAction: .refresh)
                })
    }

    private func agentRow(_ agent: AgentSpaceAgentCard) -> some View {
        ListRow(label: .avatar(title: agent.displayName,
                               description: agent.rowSubtitle,
                               icon: avatar(for: agent)),
                kind: .navigationLink {
                    context.send(viewAction: .selectAgent(agentID: agent.agentID))
                })
                .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.agent(agent.matrixUserID))
    }

    @ViewBuilder
    private func avatar(for agent: AgentSpaceAgentCard) -> some View {
        if dynamicTypeSize < .accessibility3 {
            LoadableAvatarImage(url: agent.avatarMXC.flatMap(URL.init(string:)),
                                name: agent.displayName,
                                contentID: agent.matrixUserID,
                                avatarSize: .user(on: .startChat),
                                mediaProvider: context.mediaProvider)
                .dynamicTypeSize(dynamicTypeSize < .accessibility1 ? dynamicTypeSize : .accessibility1)
                .accessibilityHidden(true)
        }
    }

    // MARK: States

    private var provisioningState: some View {
        FullscreenDialog(horizontalPadding: 24) {
            VStack(spacing: 16) {
                TitleAndIcon(title: UntranslatedL10n.screenAgentSpacesProvisioningTitle,
                             icon: \.host,
                             iconStyle: .defaultSolid)

                Text(UntranslatedL10n.screenAgentSpacesProvisioningSubtitle)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)

                ProgressView()
            }
        } bottomContent: {
            EmptyView()
        }
    }

    private var failureState: some View {
        FullscreenDialog(horizontalPadding: 24) {
            TitleAndIcon(title: UntranslatedL10n.screenAgentSpacesErrorTitle,
                         icon: \.error,
                         iconStyle: .alertSolid)
                .accessibilityIdentifier(A11yIdentifiers.agentSpacesScreen.error)
        } bottomContent: {
            Button(L10n.actionRetry) {
                context.send(viewAction: .retry)
            }
            .buttonStyle(.compound(.primary))
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                context.send(viewAction: .showSettings)
            } label: {
                LoadableAvatarImage(url: context.viewState.userAvatarURL,
                                    name: context.viewState.userDisplayName,
                                    contentID: context.viewState.userID,
                                    avatarSize: .user(on: .spaces),
                                    mediaProvider: context.mediaProvider)
                    .compositingGroup()
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.commonSettings)
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            addMenu
        }

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

struct AgentSpacesScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    static let failedSpaceViewModel = makeViewModel(companyReadFails: true)
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
        .previewDisplayName("Company read failed")

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

    static func makeViewModel(companyReadFails: Bool = false, personalAgents: Bool = true, hasSpaces: Bool = true) -> AgentSpacesScreenViewModel {
        let personal = AgentSpaceSummary(orgID: "org-personal", name: "Personal", kind: .solo, avatarMXC: nil, agentCount: 1)
        let acme = AgentSpaceSummary(orgID: "org-acme", name: "Acme Corp", kind: .company, avatarMXC: nil, agentCount: 2)
        let bakery = AgentSpaceSummary(orgID: "org-bakery", name: "Corner Bakery", kind: .company, avatarMXC: nil, agentCount: 0)

        let service = AgentPlatformServiceMock()
        service.listMyAgentSpacesReturnValue = .success(.init(spaces: hasSpaces ? [personal, acme, bakery] : [], provisioningStatus: .ready))
        service.fetchAgentSpaceOrgIDClosure = { orgID in
            switch orgID {
            case personal.orgID where !personalAgents:
                return .success(.init(orgID: orgID, name: personal.name, kind: .solo, avatarMXC: nil, industry: nil, website: nil, agents: []))
            case personal.orgID:
                return .success(.init(orgID: orgID, name: personal.name, kind: .solo, avatarMXC: nil, industry: nil, website: nil,
                                      agents: [.init(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md",
                                                     displayName: "Anna Kovalchuk · assistant", avatarMXC: nil, kind: "personal_assistant",
                                                     visibility: "public", lifecycleState: "active", presence: .online,
                                                     roomCount: 4, activeToolCount: 2)]))
            case acme.orgID where companyReadFails:
                return .failure(.serverError(status: 500))
            case acme.orgID:
                return .success(.init(orgID: orgID, name: acme.name, kind: .company, avatarMXC: nil, industry: "Logistics", website: "acme.com",
                                      agents: [.init(agentID: "agent-2", matrixUserID: "@agent-acme-sales:spiral.md",
                                                     displayName: "Sales · Acme Corp", avatarMXC: nil, kind: "sales",
                                                     visibility: "public", lifecycleState: "active", presence: .online,
                                                     roomCount: 2, activeToolCount: 1),
                                               .init(agentID: "agent-3", matrixUserID: "@agent-acme-support:spiral.md",
                                                     displayName: "Support · Acme Corp", avatarMXC: nil, kind: "support",
                                                     visibility: "private", lifecycleState: "active", presence: .offline,
                                                     roomCount: 1, activeToolCount: 0)]))
            default:
                return .success(.init(orgID: orgID, name: bakery.name, kind: .company, avatarMXC: nil, industry: nil, website: nil, agents: []))
            }
        }

        return AgentSpacesScreenViewModel(userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@owner:spiral.md")))),
                                          agentPlatformService: service)
    }
}
