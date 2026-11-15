//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents
import SwiftUI

struct UserDetailsEditScreen: View {
    @Bindable var context: UserDetailsEditScreenViewModel.Context
    @FocusState private var focus: Bool
    
    var body: some View {
        Form {
            Section {
                avatar
            } footer: {
                Text(context.viewState.currentUserProfile.id)
                    .frame(maxWidth: .infinity)
                    .font(.compound.bodyLG)
                    .foregroundColor(.compound.textPrimary)
                    .padding(.bottom, 16)
            }
            
            nameSection
            
            // AGENT-PLATFORM: feed (Brief 0082)
            if context.viewState.bio != .unavailable {
                bioSection
            }
        }
        .spiralGroupedList() // AGENT-PLATFORM (Brief 0083): Spiral's grouped list, was `compoundList()`.
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(L10n.screenEditProfileTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(context.viewState.canSave)
        .toolbar { toolbar }
        .alert(item: $context.alertInfo)
    }
    
    // MARK: - Private
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if context.viewState.canSave {
                Button(L10n.actionCancel) {
                    context.send(viewAction: .cancel)
                }
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
    
    private var avatar: some View {
        Button {
            context.send(viewAction: .presentMediaSource)
        } label: {
            OverridableAvatarImage(overrideURL: context.viewState.localMedia?.thumbnailURL,
                                   url: context.viewState.selectedAvatarURL,
                                   name: context.viewState.currentUserProfile.displayName,
                                   contentID: context.viewState.currentUserProfile.id,
                                   shape: .circle,
                                   avatarSize: .user(on: .editUserDetails),
                                   mediaProvider: context.mediaProvider)
                .confirmationDialog("", isPresented: $context.showMediaSheet) {
                    mediaActionSheet
                }
        }
        .buttonStyle(EditAvatarButtonStyle())
        .disabled(!context.viewState.canEditAvatar)
        .accessibilityLabel(L10n.a11yEditAvatar)
        .frame(maxWidth: .infinity, alignment: .center)
        .listRowBackground(Color.clear)
    }
    
    private var nameSection: some View {
        Section {
            ListRow(label: .plain(title: L10n.screenEditProfileDisplayNamePlaceholder),
                    kind: .textField(text: $context.name, axis: .horizontal))
                .focused($focus)
                .disabled(!context.viewState.canEditDisplayName)
        } header: {
            Text(L10n.screenEditProfileDisplayName)
                .compoundListSectionHeader()
        }
    }
    
    // AGENT-PLATFORM: feed (Brief 0082, decision 284): one plain-text line, counted as the backend counts it.
    private var bioSection: some View {
        Section {
            switch context.viewState.bio {
            case .unavailable:
                EmptyView()
            case .loading:
                // AGENT-PLATFORM (Brief 0083, question 359): the field's place. A `Text`, as a redacted `TextField` may not draw as one.
                ListRow(kind: .custom {
                    Text(UntranslatedL10n.screenEditProfileBioPlaceholder)
                        .spiralLoadingSlot(true, label: L10n.commonLoading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(ListRowPadding.textFieldInsets)
                })
            case .loadFailed:
                // An error row as upstream draws one: the error icon and its description under the title.
                ListRow(label: .plain(title: L10n.actionTryAgain,
                                      description: UntranslatedL10n.screenEditProfileBioLoadFailed,
                                      role: .error),
                        kind: .button { context.send(viewAction: .retryLoadingBio) })
                    .accessibilityIdentifier(A11yIdentifiers.feedBioEditor.loadFailed)
            case .loaded:
                ListRow(label: .plain(title: UntranslatedL10n.screenEditProfileBioPlaceholder),
                        kind: .textField(text: $context.bio, axis: .horizontal))
                    .focused($focus)
                    .accessibilityIdentifier(A11yIdentifiers.feedBioEditor.field)
            }
        } header: {
            Text(UntranslatedL10n.screenEditProfileBio)
                .compoundListSectionHeader()
        } footer: {
            if context.viewState.bio != .loadFailed {
                bioFooter
            }
        }
    }
    
    private var bioFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(context.viewState.isBioTooLong ? UntranslatedL10n.screenEditProfileBioTooLong(FeedBio.maxLength) : UntranslatedL10n.screenEditProfileBioFooter)
            Spacer(minLength: 0)
            Text(UntranslatedL10n.screenEditProfileBioCount(context.viewState.bioLength, FeedBio.maxLength))
                .monospacedDigit()
                .accessibilityLabel(UntranslatedL10n.a11yEditProfileBioCount(context.viewState.bioLength, FeedBio.maxLength))
                .accessibilityIdentifier(A11yIdentifiers.feedBioEditor.count)
                .spiralLoadingSlot(context.viewState.bio == .loading, label: L10n.commonLoading) // AGENT-PLATFORM (Brief 0083, question 359)
        }
        // Before the footer style, which would otherwise colour it secondary.
        .foregroundStyle(context.viewState.isBioTooLong ? .compound.textCriticalPrimary : .compound.textSecondary)
        .compoundListSectionFooter()
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

// AGENT-PLATFORM (Brief 0083, lane settings): gated.
struct UserDetailsEditScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let viewModel = makeViewModel()
    static let readOnlyViewModel = makeViewModel(canChangeProfile: false)
    // AGENT-PLATFORM: feed (Brief 0082)
    static let bioViewModel = makeViewModel(bio: .success("Gardener, hiker, bad at chess."))
    static let longBioViewModel = makeViewModel(bio: .success(String(repeating: "Gardener, hiker. ", count: 10)))
    static let bioLoadFailedViewModel = makeViewModel(bio: .failure(.sdkError(ClientProxyMockError.generic)))
    static let bioLoadingViewModel = makeViewModel(bioIsLoading: true) // AGENT-PLATFORM (Brief 0083, question 359)
    
    static var previews: some View {
        bioPreview(viewModel, name: "Default")
        bioPreview(readOnlyViewModel, name: "Read Only")
        
        bioPreview(bioViewModel, name: "Bio")
        bioPreview(longBioViewModel, name: "Bio too long")
        bioPreview(bioLoadFailedViewModel, name: "Bio load failed")
        
        ElementNavigationStack {
            UserDetailsEditScreen(context: bioLoadingViewModel.context)
        }
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Bio loading")
    }
    
    private static func bioPreview(_ viewModel: UserDetailsEditScreenViewModel, name: String) -> some View {
        ElementNavigationStack {
            UserDetailsEditScreen(context: viewModel.context)
        }
        .snapshotPreferences(expect: viewModel.context.observe(\.viewState.bio).map { bio in
            bio != .loading
        })
        .previewDisplayName(name)
    }
    
    static func makeViewModel(canChangeProfile: Bool = true, bio: Result<String?, ClientProxyError>? = nil, bioIsLoading: Bool = false) -> UserDetailsEditScreenViewModel {
        let clientProxy = ClientProxyMock(.init(userID: "@stefan:matrix.org",
                                                displayName: "Stefan",
                                                canChangeAvatar: canChangeProfile,
                                                canChangeDisplayName: canChangeProfile,
                                                canSetBio: bio != nil || bioIsLoading))
        if let bio {
            clientProxy.userBioReturnValue = bio
        }
        if bioIsLoading {
            clientProxy.userBioClosure = {
                try? await Task.sleep(for: .seconds(3600))
                return .success(nil)
            }
        }
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        
        return UserDetailsEditScreenViewModel(userSession: userSession,
                                              mediaUploadingPreprocessor: .init(userSettings: .mock()),
                                              appMediator: AppMediatorMock(.init()),
                                              userIndicatorController: UserIndicatorControllerMock())
    }
}
