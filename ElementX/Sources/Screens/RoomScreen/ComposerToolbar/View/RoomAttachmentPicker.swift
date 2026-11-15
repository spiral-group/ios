//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI
import WysiwygComposer

struct RoomAttachmentPicker: View {
    @ObservedObject var context: ComposerToolbarViewModel.Context
    
    var body: some View {
        // Use a menu instead of the popover/sheet shown in Figma because overriding the colour scheme
        // results in a rendering bug on 17.1: https://github.com/element-hq/element-x-ios/issues/2157
        Menu {
            menuContent
        } label: {
            CompoundIcon(\.plus,
                         size: Compound.supportsGlass ? .medium : .small,
                         relativeTo: .compound.headingLG)
        }
        .buttonStyle(ComposerToolbarButtonStyle())
        // AGENT-PLATFORM: Element's "Add to timeline" reads «Додати до стрічки» in uk, where «стрічка» names the Feed tab.
        .accessibilityLabel(L10n.richTextEditorA11yAddAttachment)
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.composerToolbar.openComposeOptions)
    }
    
    // AGENT-PLATFORM (Brief 0083): grouped as Messages groups its "+" menu: the camera, the library, files and
    // location first; then a poll and what the room's agents make; text formatting, a way of typing, last. Element
    // listed text formatting first and the camera sixth.
    var menuContent: some View {
        VStack(alignment: .leading, spacing: 0.0) {
            Button {
                context.send(viewAction: .attach(.camera))
            } label: {
                Label(L10n.screenRoomAttachmentSourceCamera, icon: \.takePhoto)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerCamera)

            Button {
                context.send(viewAction: .attach(.photoLibrary))
            } label: {
                Label(L10n.screenRoomAttachmentSourceGallery, icon: \.image)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerPhotoLibrary)

            Button {
                context.send(viewAction: .attach(.file))
            } label: {
                Label(L10n.screenRoomAttachmentSourceFiles, icon: \.attachment)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerDocuments)

            if context.viewState.isLocationSharingEnabled {
                Button {
                    context.send(viewAction: .attach(.location))
                } label: {
                    Label(L10n.screenRoomAttachmentSourceLocation, icon: \.locationPin)
                }
                .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerLocation)
            }

            Divider()

            Button {
                context.send(viewAction: .attach(.poll))
            } label: {
                Label(L10n.screenRoomAttachmentSourcePoll, icon: \.polls)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerPoll)

            // AGENT-PLATFORM (Brief 0066 step 6): an Interactive Post is
            // asked for here and generated in the DM with the agent picked.
            Button {
                context.send(viewAction: .presentInteractivePostAgentPicker)
            } label: {
                Label(UntranslatedL10n.screenRoomAttachmentInteractivePost, icon: \.extensions)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerInteractivePost) // AGENT-PLATFORM (decision 146)

            // AGENT-PLATFORM: the "Agents" item opens the
            // agent bottom-sheet (room → agent → tool). Brief 0035/0036.
            Button {
                context.send(viewAction: .presentAgentTools)
            } label: {
                Label(UntranslatedL10n.screenRoomAttachmentAgentTools, icon: \.userProfile)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerAgentTools) // AGENT-PLATFORM (decision 146)

            Divider()

            Button {
                context.send(viewAction: .enableTextFormatting)
            } label: {
                Label(L10n.screenRoomAttachmentTextFormatting, icon: \.textFormatting)
            }
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.attachmentPickerTextFormatting)
        }
    }
}

struct RoomAttachmentPicker_Previews: PreviewProvider, TestablePreview {
    static let viewModel = makeViewModel()
    
    static func makeViewModel() -> ComposerToolbarViewModel {
        let userSettings = UserSettings.mock()
        
        return ComposerToolbarViewModel(roomProxy: JoinedRoomProxyMock(.init()),
                                        wysiwygViewModel: WysiwygComposerViewModel(),
                                        completionSuggestionService: CompletionSuggestionServiceMock(configuration: .init()),
                                        mediaProvider: MediaProviderMock(.init()),
                                        mentionDisplayHelper: ComposerMentionDisplayHelper.mock,
                                        userSettings: userSettings,
                                        analyticsService: AnalyticsServiceMock(.init()),
                                        composerDraftService: ComposerDraftServiceMock(.init()))
    }
    
    static var previews: some View {
        RoomAttachmentPicker(context: viewModel.context)
    }
}
