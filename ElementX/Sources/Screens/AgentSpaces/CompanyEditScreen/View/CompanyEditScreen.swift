//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Edit a company space's profile (Brief 0039 S4b) — the
/// RoomDetailsEditScreen anatomy: centred logo avatar button with the
/// canonical media confirmationDialog, labelled NAME / INDUSTRY / WEBSITE
/// sections, Save disabled until something changed.
struct CompanyEditScreen: View {
    @Bindable var context: CompanyEditScreenViewModel.Context
    
    private enum Focus { case name, industry, website }
    @FocusState private var focus: Focus?
    
    var body: some View {
        Form {
            avatar
            nameSection
            industrySection
            websiteSection
        }
        .compoundList()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(UntranslatedL10n.screenCompanyEditTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .alert(item: $context.alertInfo)
        .interactiveDismissDisabled(context.viewState.isSaving)
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.actionCancel) {
                context.send(viewAction: .cancel)
            }
            .disabled(context.viewState.isSaving)
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionSave) {
                context.send(viewAction: .save)
                focus = nil
            }
            .disabled(!context.viewState.canSave)
        }
    }
    
    // RoomDetailsEdit canon: centred avatar; the local replacement
    // thumbnail overrides the current logo until Save.
    private var avatar: some View {
        Button {
            context.send(viewAction: .presentMediaSource)
        } label: {
            OverridableAvatarImage(overrideURL: context.viewState.localMedia?.thumbnailURL,
                                   url: context.viewState.logoMXC.flatMap(URL.init(string:)),
                                   name: context.viewState.initialName,
                                   contentID: context.viewState.orgID,
                                   shape: .roundedRect,
                                   avatarSize: .room(on: .editSpaceDetails),
                                   mediaProvider: context.mediaProvider)
                .accessibilityLabel(L10n.a11yEditAvatar)
                .confirmationDialog("", isPresented: $context.showMediaSheet) {
                    mediaActionSheet
                }
        }
        .buttonStyle(EditAvatarButtonStyle())
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowBackground(Color.clear)
    }
    
    private var nameSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenCreateCompanyNamePlaceholder),
                    kind: .textField(text: $context.name, axis: .horizontal))
                .focused($focus, equals: .name)
        } header: {
            Text(UntranslatedL10n.screenCreateCompanyNameLabel)
                .compoundListSectionHeader()
        }
    }
    
    private var industrySection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenCreateCompanyIndustryExample),
                    kind: .textField(text: $context.industry, axis: .horizontal))
                .focused($focus, equals: .industry)
        } header: {
            Text(UntranslatedL10n.screenCreateCompanyIndustryPlaceholder)
                .compoundListSectionHeader()
        }
    }
    
    private var websiteSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenCreateCompanyWebsiteExample),
                    kind: .textField(text: $context.website, axis: .horizontal))
                .focused($focus, equals: .website)
        } header: {
            Text(UntranslatedL10n.screenCreateCompanyWebsitePlaceholder)
                .compoundListSectionHeader()
        }
    }
    
    @ViewBuilder
    private var mediaActionSheet: some View {
        Button {
            context.send(viewAction: .displayCameraPicker)
        } label: {
            Text(L10n.actionTakePhoto)
        }
        
        Button {
            context.send(viewAction: .displayMediaPicker)
        } label: {
            Text(L10n.actionChoosePhoto)
        }
        
        Button {
            context.send(viewAction: .displayFilePicker)
        } label: {
            Text(L10n.actionChooseFile)
        }
        
        if context.viewState.showDeleteImageAction {
            Button(role: .destructive) {
                context.send(viewAction: .removeImage)
            } label: {
                Text(L10n.actionRemove)
            }
        }
    }
}

// MARK: - Previews

struct CompanyEditScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = CompanyEditScreenViewModel(detail: .init(orgID: "org-acme",
                                                                    name: "Acme Corporation",
                                                                    kind: .company,
                                                                    avatarMXC: nil,
                                                                    industry: "Logistics",
                                                                    website: "acme.com",
                                                                    agents: []),
                                                      agentPlatformService: AgentPlatformServiceMock(),
                                                      userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init()))),
                                                      userIndicatorController: UserIndicatorControllerMock(),
                                                      appSettings: .volatile())
    
    static var previews: some View {
        ElementNavigationStack {
            CompanyEditScreen(context: viewModel.context)
        }
    }
}
