//
// Copyright 2025 Element Creations Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The agent's «Изменить профиль» (decision 194): pushed, the avatar with its
/// camera menu and the handle under it, and the name. Everything else is in
/// the agent screen's «Настройки».
struct AgentEditScreen: View {
    @Bindable var context: AgentEditScreenViewModel.Context
    @FocusState private var focus: Bool
    
    var body: some View {
        content
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(UntranslatedL10n.screenAgentEditTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(context.viewState.canSave)
            .toolbar { toolbar }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .alert(item: $context.alertInfo)
    }
    
    @ViewBuilder
    private var content: some View {
        switch context.viewState.loadState {
        case .loading:
            // Fast data → a delayed centred spinner, no skeleton flicker
            // (CODEBASE/14 §3).
            DelayedProgressView()
        case .failure:
            loadFailureState
        case .loaded(let schema):
            form(schema)
        }
    }
    
    private func form(_ schema: AgentEditSchema) -> some View {
        Form {
            avatarSection
            
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenAgentEditDisplayNameSection),
                        kind: .textField(text: $context.displayName, axis: .horizontal))
                    .focused($focus)
                    .onChange(of: context.displayName) { _, newValue in
                        if newValue.count > schema.displayName.maxLength {
                            context.displayName = String(newValue.prefix(schema.displayName.maxLength))
                        }
                    }
            } header: {
                Text(UntranslatedL10n.screenAgentEditDisplayNameSection)
                    .compoundListSectionHeader()
            }
        }
        .compoundList()
    }
    
    // «Изменить профиль» canon: the avatar centred with its media menu, the
    // handle under it; a picked image shows until Save, which uploads it
    // (`clientProxy.uploadMedia` → PATCH `avatar_mxc`).
    private var avatarSection: some View {
        Section {
            Button {
                context.send(viewAction: .presentMediaSource)
            } label: {
                OverridableAvatarImage(overrideURL: context.viewState.localMedia?.thumbnailURL,
                                       url: context.viewState.avatarMXC.flatMap(URL.init(string:)),
                                       name: context.viewState.card.displayName,
                                       contentID: context.viewState.card.matrixUserID,
                                       shape: .circle,
                                       avatarSize: .user(on: .editUserDetails),
                                       mediaProvider: context.mediaProvider)
                    .confirmationDialog("", isPresented: $context.showMediaSheet) {
                        mediaActionSheet
                    }
            }
            .buttonStyle(EditAvatarButtonStyle())
            .accessibilityLabel(L10n.a11yEditAvatar)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
        } footer: {
            Text(context.viewState.card.matrixUserID)
                .frame(maxWidth: .infinity)
                .font(.compound.bodyLG)
                .foregroundColor(.compound.textPrimary)
                .padding(.bottom, 16)
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
    
    private var loadFailureState: some View {
        VStack(spacing: 24) {
            TitleAndIcon(title: UntranslatedL10n.screenAgentEditLoadFailure,
                         icon: \.error,
                         iconStyle: .alertSolid)
                .padding(.horizontal, 24)
            
            Button(L10n.actionRetry) {
                context.send(viewAction: .retry)
            }
            .buttonStyle(.compound(.primary))
            .padding(.horizontal, 16)
        }
        .padding(.top, 40)
    }
    
    /// «Изменить профиль» canon: Cancel replaces the back chevron while
    /// there is something to save.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if context.viewState.canSave {
                Button(L10n.actionCancel) {
                    context.send(viewAction: .cancel)
                }
                .disabled(context.viewState.isSaving)
            }
        }
        
        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.actionSave) {
                context.send(viewAction: .save)
                focus = false
            }
            .disabled(!context.viewState.canSave)
        }
    }
}

// MARK: - Previews

struct AgentEditScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    
    static var previews: some View {
        ElementNavigationStack {
            AgentEditScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.loadState).map { if case .loading = $0 { false } else { true } })
    }
    
    static func makeViewModel() -> AgentEditScreenViewModel {
        let card = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md", displayName: "Anna Kovalchuk · assistant",
                                       avatarMXC: nil, kind: "personal_assistant", visibility: "public", lifecycleState: "active",
                                       presence: .online, roomCount: 2, activeToolCount: 1)
        
        let service = AgentPlatformServiceMock()
        service.fetchAgentEditSchemaAgentIDReturnValue = .success(.init(agentID: card.agentID,
                                                                        kind: card.kind,
                                                                        displayName: .init(minLength: 1, maxLength: 64),
                                                                        persona: nil))
        service.fetchAgentReadModelAgentIDReturnValue = .success(.init(agentID: card.agentID,
                                                                       matrixUserID: card.matrixUserID,
                                                                       displayName: card.displayName,
                                                                       avatarMXC: nil,
                                                                       kind: card.kind,
                                                                       visibility: card.visibility,
                                                                       lifecycleState: card.lifecycleState,
                                                                       organizationID: "org-1",
                                                                       roomCount: card.roomCount,
                                                                       activeToolCount: card.activeToolCount,
                                                                       configVersionNumber: 1,
                                                                       persona: nil))
        
        return AgentEditScreenViewModel(agent: card,
                                        agentPlatformService: service,
                                        userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init()))),
                                        userIndicatorController: UserIndicatorControllerMock(),
                                        appSettings: .volatile())
    }
}
