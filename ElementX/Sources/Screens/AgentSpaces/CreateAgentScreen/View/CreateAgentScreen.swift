//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Provision a role agent inside a company space (artboard 0037-F) —
/// sheet-form: role selection rows, optional display-name override,
/// identity explainer footer.
struct CreateAgentScreen: View {
    @Bindable var context: CreateAgentScreenViewModel.Context
    
    var body: some View {
        Form {
            Section {
                ForEach(CreateAgentRole.allCases, id: \.self) { role in
                    ListRow(label: .plain(title: role.title),
                            details: context.role == role ? .icon(CompoundIcon(\.check)) : nil,
                            kind: .button {
                                context.send(viewAction: .selectRole(role))
                            })
                }
            } header: {
                Text(UntranslatedL10n.screenCreateAgentRoleSection)
                    .compoundListSectionHeader()
            }
            
            Section {
                ListRow(label: .plain(title: context.viewState.defaultDisplayName),
                        kind: .textField(text: $context.displayName, axis: .horizontal))
            } header: {
                Text(L10n.commonName)
                    .compoundListSectionHeader()
            }
            
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenCreateAgentRoleBriefPlaceholder),
                        kind: .textField(text: $context.roleBrief, axis: .vertical))
                    .lineLimit(3, reservesSpace: false)
            } header: {
                Text(UntranslatedL10n.screenCreateAgentRoleBriefSection)
                    .compoundListSectionHeader()
            } footer: {
                Text(UntranslatedL10n.screenCreateAgentRoleBriefFooter)
                    .compoundListSectionFooter()
            }
            
            Section {
                EmptyView()
            } footer: {
                Text(UntranslatedL10n.screenCreateAgentFooter)
                    .compoundListSectionFooter()
            }
        }
        .compoundList()
        .navigationTitle(UntranslatedL10n.screenCreateAgentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .alert(item: $context.alertInfo)
        .interactiveDismissDisabled(context.viewState.isCreating)
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.actionCancel, role: .cancel) {
                context.send(viewAction: .cancel)
            }
            .disabled(context.viewState.isCreating)
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionCreate) {
                context.send(viewAction: .create)
            }
            .disabled(!context.viewState.canCreate)
        }
    }
}

// MARK: - Previews

struct CreateAgentScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = CreateAgentScreenViewModel(companyID: "org-acme",
                                                      companyName: "Acme Corp",
                                                      agentPlatformService: AgentPlatformServiceMock())
    
    static var previews: some View {
        ElementNavigationStack {
            CreateAgentScreen(context: viewModel.context)
        }
    }
}
