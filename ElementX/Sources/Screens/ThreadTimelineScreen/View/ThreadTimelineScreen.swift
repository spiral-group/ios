//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct ThreadTimelineScreen: View {
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled // AGENT-PLATFORM (Brief 0083, question 359)
    
    @ObservedObject private var context: ThreadTimelineScreenViewModelType.Context
    @ObservedObject private var timelineContext: TimelineViewModelType.Context
    private let composerToolbar: ComposerToolbar
    
    init(context: ThreadTimelineScreenViewModelType.Context,
         timelineContext: TimelineViewModelType.Context,
         composerToolbar: ComposerToolbar) {
        self.context = context
        self.timelineContext = timelineContext
        self.composerToolbar = composerToolbar
    }
    
    var body: some View {
        TimelineView(timelineContext: timelineContext)
            .timelineUnderComposerBar() // AGENT-PLATFORM (Brief 0083, decision 334): as in the room
            .timelineUnderHeader(isEnabled: !isVoiceOverEnabled) // AGENT-PLATFORM (Brief 0083, question 359): as in the room
            .chatBackground() // AGENT-PLATFORM (Brief 0083, question 357)
            .toolbarRole(RoomHeaderView.toolbarRole)
            .navigationTitle(L10n.commonThread)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .timelineHeaderBackground() // AGENT-PLATFORM (Brief 0083, question 359): as in the room
            .navigationBarBackButtonHidden(isMessageSelectionActive)
            .timelineMediaPreview(viewModel: $context.mediaPreviewViewModel)
            .overlay(alignment: .top) {
                FloatingDateBadge(dateText: timelineContext.floatingDate?.formattedDateSeparator()) {
                    timelineContext.send(viewAction: .scrollToFirstItemForCurrentDate)
                }
                .onChatBackground() // AGENT-PLATFORM (Brief 0083, question 359)
                .padding(.top, 13)
            }
            .overlay(alignment: .bottomTrailing) {
                TimelineScrollButton(isHidden: !timelineContext.viewState.shouldShowScrollToBottomButton) {
                    timelineContext.send(viewAction: .scrollToBottom)
                }
            }
            .timelineComposerBar { // AGENT-PLATFORM (Brief 0083, decision 334): as in the room
                VStack(spacing: 0) {
                    composer
                        .padding(.top, 8)
                        .spiralComposerBar(scrollsUnder: true) // AGENT-PLATFORM (Brief 0083): the room's composer bar
                        .environmentObject(timelineContext)
                        .environment(\.timelineContext, timelineContext)
                        // Make sure the reply header honours the hideTimelineMedia setting too.
                        .environment(\.shouldAutomaticallyLoadImages, !timelineContext.viewState.hideTimelineMedia)
                        .collapsedInPlace(isMessageSelectionActive)
                    
                    if isMessageSelectionActive {
                        TimelineMessageSelectionActionBar(context: timelineContext)
                    }
                }
            } floating: {
                composerSuggestions
            }
    }
    
    private var isMessageSelectionActive: Bool {
        timelineContext.viewState.messageSelection.isActive
    }
    
    @ViewBuilder
    private var composer: some View {
        if context.viewState.canSendMessage {
            composerToolbar
        } else {
            ComposerDisabledView()
        }
    }
    
    // AGENT-PLATFORM (question 357): as in the room, they go with the composer they belong to.
    @ViewBuilder
    private var composerSuggestions: some View {
        if context.viewState.canSendMessage, !isMessageSelectionActive {
            composerToolbar.floatingSuggestions
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // .principal + .primaryAction works better than .navigation leading + trailing
        // as the latter disables interaction in the action button for rooms with long names
        ToolbarItem(placement: .principal) {
            RoomHeaderView(roomName: L10n.commonThread,
                           roomSubtitle: context.viewState.roomTitle,
                           roomAvatar: context.viewState.roomAvatar,
                           dmRecipientDetails: context.viewState.dmRecipientDetails,
                           roomHistorySharingState: context.viewState.roomHistorySharingState,
                           typing: timelineContext.viewState.headerTyping, // AGENT-PLATFORM (Brief 0083, question 359)
                           mediaProvider: context.mediaProvider) {
                // There is no action but the iOS 26 designs have it looking like a button.
            }
            .onChatBackground() // AGENT-PLATFORM (Brief 0083, question 359)
        }
        
        if isMessageSelectionActive {
            TimelineMessageSelectionToolbar {
                timelineContext.send(viewAction: .clearMessageSelection)
            }
        }
    }
}
