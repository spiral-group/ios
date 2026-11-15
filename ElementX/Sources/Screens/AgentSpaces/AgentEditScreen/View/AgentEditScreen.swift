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
    
    /// The final form from the first frame. The card always has something to show, so nothing
    /// replaces it; until the limits arrive the name can't be checked, and stays closed.
    private var content: some View {
        Form {
            avatarSection
            
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenAgentEditDisplayNameSection),
                        kind: .textField(text: $context.displayName, axis: .horizontal))
                    .focused($focus)
                    .disabled(context.viewState.schema == nil)
                    .onChange(of: context.displayName) { _, newValue in
                        if let maxLength = context.viewState.schema?.displayName.maxLength, newValue.count > maxLength {
                            context.displayName = String(newValue.prefix(maxLength))
                        }
                    }
            } header: {
                Text(UntranslatedL10n.screenAgentEditDisplayNameSection)
                    .compoundListSectionHeader()
            }
            
            if context.viewState.loadState == .failure {
                AgentSpacesRetryErrorSection(title: UntranslatedL10n.screenAgentEditLoadFailure) {
                    context.send(viewAction: .retry)
                }
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

struct AgentEditScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    // Brief 0083, question 359: the card fills the form while the name's limits are on their way.
    static let loadingViewModel = makeViewModel(schema: nil)
    static let failedViewModel = makeViewModel(schema: .failure(.serverError(status: 500)))
    
    static var previews: some View {
        ElementNavigationStack {
            AgentEditScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.loadState).map { $0 != .loading })
        .previewDisplayName("Default")
        
        ElementNavigationStack {
            AgentEditScreen(context: loadingViewModel.context)
        }
        .previewDisplayName("Loading")
        
        ElementNavigationStack {
            AgentEditScreen(context: failedViewModel.context)
        }
        .snapshotPreferences(expect: failedViewModel.context.observe(\.viewState.loadState).map { $0 == .failure })
        .previewDisplayName("Failed")
    }
    
    private static let card = AgentSpaceAgentCard(agentID: "agent-1", matrixUserID: "@assistant-owner:spiral.md", displayName: "Anna Kovalchuk · assistant",
                                                  avatarMXC: nil, kind: "personal_assistant", visibility: "public", lifecycleState: "active",
                                                  roomCount: 2, activeToolCount: 1)
    
    private static let schema = AgentEditSchema(agentID: card.agentID,
                                                kind: card.kind,
                                                displayName: .init(minLength: 1, maxLength: 64),
                                                persona: nil)
    
    /// A `nil` schema is a read that never answers.
    static func makeViewModel(schema: Result<AgentEditSchema, AgentPlatformError>? = .success(schema)) -> AgentEditScreenViewModel {
        let service = AgentPlatformServiceMock()
        if let schema {
            service.fetchAgentEditSchemaAgentIDReturnValue = schema
        } else {
            service.fetchAgentEditSchemaAgentIDClosure = { _ in
                try? await Task.sleep(for: .seconds(3600))
                return .failure(.serverError(status: 500))
            }
        }
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
        service.fetchAgentRoomsAgentIDReturnValue = .success([])
        service.listVerificationsForAgentAgentIDReturnValue = .success([])
        
        return AgentEditScreenViewModel(agent: card,
                                        agentPlatformService: service,
                                        store: AgentsStore(service: service),
                                        userSession: UserSessionMock(.init(clientProxy: ClientProxyMock(.init()))),
                                        userIndicatorController: UserIndicatorControllerMock())
    }
}
