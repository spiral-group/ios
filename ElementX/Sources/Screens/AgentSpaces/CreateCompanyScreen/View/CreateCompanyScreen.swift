//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Create a company space (artboard 0037-H), rebuilt in Brief 0039 S3 on
/// the CreateRoomScreen canon: the company logo sits in the NAME section
/// header as an avatar button (confirmationDialog with Take photo /
/// Choose photo / Choose file / Remove), the logo uploads deferred at
/// Create time, INDUSTRY/WEBSITE stay Compound `ListRow` rows.
struct CreateCompanyScreen: View {
    @Bindable var context: CreateCompanyScreenViewModel.Context
    @FocusState private var focus: Focus?
    
    private enum Focus {
        case name
    }
    
    var body: some View {
        Form {
            companySection
            detailsSection
        }
        .compoundList()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(UntranslatedL10n.screenCreateCompanyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .alert(item: $context.alertInfo)
        .interactiveDismissDisabled(context.viewState.isCreating)
    }
    
    private var nameTextFieldShape: AnyShape {
        if #available(iOS 26, *) {
            AnyShape(ConcentricRectangle(corners: .concentric(minimum: 26)))
        } else {
            AnyShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // The CreateRoom `roomSection` anatomy: avatar button + NAME label +
    // text field in the section header.
    private var companySection: some View {
        Section {
            EmptyView()
        } header: {
            HStack(alignment: .center, spacing: 16) {
                logoAvatarButton
                let nameLabel = if #available(iOS 26, *) {
                    UntranslatedL10n.screenCreateCompanyNameLabel
                } else {
                    UntranslatedL10n.screenCreateCompanyNameLabel.uppercased()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(nameLabel)
                        .padding(.leading, ListRowPadding.horizontal)
                        .compoundListSectionHeader()
                    
                    TextField(UntranslatedL10n.screenCreateCompanyNameLabel,
                              text: $context.name,
                              prompt: Text(UntranslatedL10n.screenCreateCompanyNamePlaceholder).foregroundColor(.compound.textSecondary),
                              axis: .horizontal)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textPrimary)
                        .tint(.compound.iconAccentTertiary)
                        .focused($focus, equals: .name)
                        .padding(.horizontal, ListRowPadding.horizontal)
                        .padding(.vertical, ListRowPadding.vertical)
                        .background(.compound.bgCanvasDefaultLevel1, in: nameTextFieldShape)
                }
            }
            .listRowInsets(.init())
            .padding(.top, 16)
        }
    }
    
    private var logoAvatarButton: some View {
        Button {
            focus = nil
            context.showAttachmentConfirmationDialog = true
        } label: {
            if let avatarImage = context.viewState.avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaledFrame(size: 70, relativeTo: .title)
                    .avatarShape(.roundedRect, size: 70)
                    .overlay(alignment: .bottomTrailing) {
                        EditAvatarBadge()
                            .scaledOffset(x: 8, y: 0, relativeTo: .title)
                    }
            } else {
                CompoundIcon(\.takePhoto, size: .medium, relativeTo: .title)
                    .foregroundColor(.compound.iconPrimary)
                    .scaledFrame(size: 50, relativeTo: .title)
                    .background(.compound.bgCanvasDefault, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.compound.borderInteractiveSecondary, lineWidth: 1)
                    }
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(L10n.a11yEditAvatar)
        .buttonStyle(.plain)
        .confirmationDialog("", isPresented: $context.showAttachmentConfirmationDialog) {
            Button(L10n.actionTakePhoto) {
                context.send(viewAction: .displayCameraPicker)
            }
            
            Button(L10n.actionChoosePhoto) {
                context.send(viewAction: .displayMediaPicker)
            }
            
            Button(L10n.actionChooseFile) {
                context.send(viewAction: .displayFilePicker)
            }
            
            if context.viewState.avatarImage != nil {
                Button(L10n.actionRemove, role: .destructive) {
                    context.send(viewAction: .removeImage)
                }
            }
        }
    }
    
    // Every field carries its own section-header label (the CreateRoom
    // topicSection anatomy — the optionality lives in the header, the row
    // placeholder shows an example).
    @ViewBuilder
    private var detailsSection: some View {
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenCreateCompanyIndustryExample),
                    kind: .textField(text: $context.industry, axis: .horizontal))
        } header: {
            Text(UntranslatedL10n.screenCreateCompanyIndustryPlaceholder)
                .compoundListSectionHeader()
        }
        
        Section {
            ListRow(label: .plain(title: UntranslatedL10n.screenCreateCompanyWebsiteExample),
                    kind: .textField(text: $context.website, axis: .horizontal))
        } header: {
            Text(UntranslatedL10n.screenCreateCompanyWebsitePlaceholder)
                .compoundListSectionHeader()
        } footer: {
            Text(UntranslatedL10n.screenCreateCompanyFooter)
                .compoundListSectionFooter()
        }
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

struct CreateCompanyScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = CreateCompanyScreenViewModel(agentPlatformService: AgentPlatformServiceMock(),
                                                        userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init()))),
                                                        userIndicatorController: UserIndicatorControllerMock(),
                                                        appSettings: .volatile())
    
    static var previews: some View {
        ElementNavigationStack {
            CreateCompanyScreen(context: viewModel.context)
        }
    }
}
