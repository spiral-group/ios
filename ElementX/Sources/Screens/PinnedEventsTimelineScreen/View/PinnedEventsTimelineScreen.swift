//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct PinnedEventsTimelineScreen: View {
    @ObservedObject var context: PinnedEventsTimelineScreenViewModel.Context
    @ObservedObject var timelineContext: TimelineViewModel.Context
    
    private var isMessageSelectionActive: Bool {
        timelineContext.viewState.messageSelection.isActive
    }
    
    private var title: String {
        let pinnedEventIDs = timelineContext.viewState.pinnedEventIDs
        guard !pinnedEventIDs.isEmpty else {
            return L10n.screenPinnedTimelineScreenTitleEmpty
        }
        return L10n.screenPinnedTimelineScreenTitle(pinnedEventIDs.count)
    }
    
    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .timelineHeaderBackground() // AGENT-PLATFORM (Brief 0083, question 359): before glass, Close reads 2.26:1 on the picture's sky
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isMessageSelectionActive {
                    TimelineMessageSelectionActionBar(context: timelineContext)
                }
            }
            .chatBackground() // AGENT-PLATFORM (Brief 0083, question 359)
            .interactiveDismissDisabled()
            .timelineMediaPreview(viewModel: $context.mediaPreviewViewModel)
    }
    
    @ViewBuilder
    private var content: some View {
        if timelineContext.viewState.pinnedEventIDs.isEmpty {
            VStack(spacing: 16) {
                BigIcon(icon: \.pin)
                Text(L10n.screenPinnedTimelineEmptyStateHeadline)
                    .font(.compound.headingSMSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                EmptyStateDescription() // AGENT-PLATFORM (Brief 0083, question 359)
                Spacer()
            }
            .padding(.top, 48)
            .padding(.horizontal, 16)
        } else {
            TimelineView(timelineContext: timelineContext)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if isMessageSelectionActive {
            TimelineMessageSelectionToolbar {
                timelineContext.send(viewAction: .clearMessageSelection)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.actionClose) {
                    context.send(viewAction: .close)
                }
            }
        }
    }
}

/// Grey reads 3.73:1 on the picture's sky in dark and 4.31:1 in light, so on the picture it takes the primary text colour.
private struct EmptyStateDescription: View {
    @Environment(\.isChatBackgroundDrawn) private var isChatBackgroundDrawn
    
    var body: some View {
        Text(L10n.screenPinnedTimelineEmptyStateDescription(L10n.actionPin))
            .font(.compound.bodyMD)
            .foregroundStyle(isChatBackgroundDrawn ? .compound.textPrimary : .compound.textSecondary)
            .multilineTextAlignment(.center)
    }
}

// MARK: - Previews

struct PinnedEventsTimelineScreen_Previews: PreviewProvider, TestablePreview {
    static let viewModel = PinnedEventsTimelineScreenViewModel(roomProxy: JoinedRoomProxyMock(.init()),
                                                               userIndicatorController: UserIndicatorControllerMock(),
                                                               userSettings: .mock(),
                                                               analyticsService: AnalyticsServiceMock(.init()))
    
    static let emptyTimelineViewModel = makeTimelineViewModel(timelineItems: [])
    static let selectingTimelineViewModel = makeTimelineViewModel(timelineItems: TimelineFixtures.default, isSelecting: true)
    
    static var previews: some View {
        ElementNavigationStack {
            PinnedEventsTimelineScreen(context: viewModel.context, timelineContext: emptyTimelineViewModel.context)
        }
        .previewDisplayName("Empty")
        
        ElementNavigationStack {
            PinnedEventsTimelineScreen(context: viewModel.context, timelineContext: selectingTimelineViewModel.context)
        }
        .previewDisplayName("Selecting")
        .snapshotPreferences(expect: selectingTimelineViewModel.context.$viewState.map(\.messageSelection.isActive))
    }
    
    static func makeTimelineViewModel(timelineItems: [RoomTimelineItemProtocol], isSelecting: Bool = false) -> TimelineViewModel {
        let eventIDs = timelineItems.compactMap { ($0 as? EventBasedTimelineItemProtocol)?.id.eventID }
        let timelineController = TimelineControllerMock(.init(timelineKind: .pinned, timelineItems: timelineItems))
        
        let timelineViewModel = TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init(name: "Preview room", pinnedEventIDs: Set(eventIDs))),
                                                  timelineController: timelineController,
                                                  userSession: UserSessionMock(.init()),
                                                  mediaPlayerProvider: MediaPlayerProviderMock(),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  appMediator: AppMediatorMock(.init()),
                                                  analyticsService: AnalyticsServiceMock(.init()),
                                                  emojiProvider: EmojiProvider(userSettings: .mock()),
                                                  linkMetadataProvider: LinkMetadataProvider(),
                                                  timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        
        if isSelecting {
            timelineViewModel.state.messageSelection.isActive = true
            timelineViewModel.state.messageSelection.selectedEventIDs = Set(eventIDs.prefix(2))
        }
        
        return timelineViewModel
    }
}
