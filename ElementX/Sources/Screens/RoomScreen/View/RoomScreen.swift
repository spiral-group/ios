//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SpiralTokens
import SwiftUI
import WysiwygComposer

struct RoomScreen: View {
    @ObservedObject private var context: RoomScreenViewModelType.Context
    @ObservedObject private var timelineContext: TimelineViewModelType.Context
    let composerToolbar: ComposerToolbar
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    
    enum MarkAsReadSource {
        case up
        case down
    }
    
    /// Which scroll button (if any) currently has the "Mark as read" pill displayed alongside it.
    /// Set when the user long-presses one of the scroll buttons; the pill anchors to that button.
    @State private var markAsReadSource: MarkAsReadSource?
    @State private var topBlockHeight: CGFloat = 0 // AGENT-PLATFORM (Brief 0083, decision 345)
    
    init(context: RoomScreenViewModelType.Context,
         timelineContext: TimelineViewModelType.Context,
         composerToolbar: ComposerToolbar) {
        self.context = context
        self.timelineContext = timelineContext
        self.composerToolbar = composerToolbar
    }
    
    var body: some View {
        TimelineView(timelineContext: timelineContext)
            // AGENT-PLATFORM (Brief 0083, decision 345): under VoiceOver the block is in the safe area's inset, not over the table.
            .environment(\.timelineHeaderBlockHeight, isVoiceOverEnabled ? 0 : topBlockHeight)
            .timelineUnderComposerBar() // AGENT-PLATFORM (Brief 0083, decision 334): it scrolls under the glass composer
            .timelineUnderHeader(isEnabled: !isVoiceOverEnabled) // AGENT-PLATFORM (Brief 0083, decision 344): and under the header
            .overlay {
                // Sits below the bottom-trailing overlay in z-order, so taps on the pill or
                // buttons still go to them; taps anywhere else dismiss the pill.
                if markAsReadSource != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissMarkAsReadPill() }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 16) {
                    HStack(spacing: 8) {
                        if markAsReadSource == .up {
                            markAsReadPill
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                        jumpToReadMarkerButton
                    }
                    HStack(spacing: 8) {
                        if markAsReadSource == .down {
                            markAsReadPill
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                        TimelineScrollButton(isHidden: !timelineContext.viewState.shouldShowScrollToBottomButton,
                                             showsBadge: timelineContext.viewState.bindings.hasNewMessagesAtBottom,
                                             onLongPress: timelineContext.viewState.offersMarkAsReadOnScrollToBottom ? { revealMarkAsReadPill(source: .down) } : nil,
                                             accessibilityIdentifier: A11yIdentifiers.roomScreen.scrollToBottom) {
                            dismissMarkAsReadPill()
                            timelineContext.send(viewAction: .scrollToBottom)
                        }
                    }
                }
                .padding()
                .animation(.elementDefault, value: markAsReadSource)
            }
            .chatBackground() // AGENT-PLATFORM (Brief 0083, question 357)
            .topBanners([
                TopBannerLayer(verticalBanners: [
                    TopBannerItem(topBlock, isVisible: isTopBlockVisible && !isVoiceOverEnabled), // AGENT-PLATFORM (Brief 0083, decision 345)
                    TopBannerItem(liveLocationBanner, isVisible: context.viewState.isSharingLiveLocation && !isVoiceOverEnabled)
                ]),
                // This can overlay on top of the stacked banners
                TopBannerLayer(knockRequestsBanner, isVisible: context.viewState.shouldSeeKnockRequests)
            ], footer: dateBadge)
            .safeAreaInset(edge: .top) {
                // When VoiceOver is enabled the scroll gestures don't trigger, so the banner never
                // hides itself and the .overlay layout above would permanently obscure the top of
                // the timeline. So whenever VoiceOver is enabled we use a safe area inset to
                // vertically stack it above the timeline instead.
                // AGENT-PLATFORM (Brief 0044): the active-tools banner joins the stack.
                if isTopBlockVisible || context.viewState.isSharingLiveLocation, isVoiceOverEnabled {
                    VStack(spacing: 0) {
                        if isTopBlockVisible {
                            topBlock
                        }
                        if context.viewState.isSharingLiveLocation {
                            liveLocationBanner
                        }
                    }
                }
            }
            .timelineComposerBar { // AGENT-PLATFORM (Brief 0083, decision 334): a bar on iOS 26+, an inset before
                VStack(spacing: 0) {
                    RoomScreenFooterView(details: context.viewState.footerDetails,
                                         mediaProvider: context.mediaProvider) { action in
                        context.send(viewAction: .footerViewAction(action))
                    }
                    
                    composer
                        .padding(.top, 8)
                        .spiralComposerBar(scrollsUnder: true) // AGENT-PLATFORM (Brief 0083): the composer's bar, shared with threads and comments
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
            .navigationBarBackButtonHidden(isMessageSelectionActive)
            .toolbarRole(.automatic) // AGENT-PLATFORM (Brief 0083, decision 344): the capsule is centred on iOS 26+ too
            .navigationTitle(L10n.screenRoomTitle) // Hidden but used for back button text.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .timelineHeaderBackground() // AGENT-PLATFORM (Brief 0083, decision 344): a clear bar with Liquid Glass
            .overlay { loadingIndicator }
            .alert(item: $context.alertInfo)
            .timelineMediaPreview(viewModel: $context.mediaPreviewViewModel)
            .onChange(of: pillSourceButtonIsVisible) { _, isVisible in
                if !isVisible {
                    dismissMarkAsReadPill()
                }
            }
            .track(screen: .Room) // AGENT-PLATFORM (Brief 0078): no Sentry view tracing.
    }
    
    private var liveLocationBanner: some View {
        LiveLocationSharingBannerView {
            context.send(viewAction: .tappedOpenLiveLocation)
        } onStop: {
            context.send(viewAction: .tappedStopLiveLocation)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 345): the pinned message and the active tools (Brief 0036), floating under the
    // header. The timeline's inset follows the block's height.
    private var isTopBlockVisible: Bool {
        context.viewState.shouldShowPinnedEventsBanner || context.viewState.shouldShowActiveToolsBanner
    }
    
    private var topBlock: some View {
        RoomTopBlock(pinned: context.viewState.shouldShowPinnedEventsBanner ? context.viewState.pinnedEventsBannerState : nil,
                     tools: context.viewState.shouldShowActiveToolsBanner ? context.viewState.activeToolsBannerState : nil,
                     onPinnedTap: { context.send(viewAction: .tappedPinnedEventsBanner) },
                     onViewAllTap: { context.send(viewAction: .viewAllPins) },
                     onToolTap: { context.send(viewAction: .rotateActiveToolsBanner) },
                     onManageTap: { context.send(viewAction: .tappedActiveToolsBanner) })
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBlockHeight = $0 }
            .onDisappear { topBlockHeight = 0 }
    }
    
    private var knockRequestsBanner: some View {
        KnockRequestsBannerView(requests: context.viewState.displayedKnockRequests,
                                onDismiss: dismissKnockRequestsBanner,
                                onAccept: context.viewState.canAcceptKnocks ? acceptKnockRequest : nil,
                                onViewAll: onViewAllKnockRequests,
                                mediaProvider: context.mediaProvider)
            .padding(.top, 16)
    }
    
    @ViewBuilder
    private var dateBadge: some View {
        if !isVoiceOverEnabled {
            FloatingDateBadge(dateText: timelineContext.floatingDate?.formattedDateSeparator()) {
                timelineContext.send(viewAction: .scrollToFirstItemForCurrentDate)
            }
            .onChatBackground() // AGENT-PLATFORM (Brief 0083, question 359)
        }
    }
    
    private func dismissKnockRequestsBanner() {
        context.send(viewAction: .dismissKnockRequests)
    }
    
    private func acceptKnockRequest(eventID: String) {
        context.send(viewAction: .acceptKnock(eventID: eventID))
    }
    
    private func onViewAllKnockRequests() {
        context.send(viewAction: .viewKnockRequests)
    }
    
    @ViewBuilder
    private var jumpToReadMarkerButton: some View {
        if timelineContext.viewState.shouldShowJumpToReadMarker {
            TimelineScrollButton(direction: .up,
                                 showsBadge: true) {
                revealMarkAsReadPill(source: .up)
            } callback: {
                dismissMarkAsReadPill()
                timelineContext.send(viewAction: .scrollToReadMarker)
            }
        }
    }
    
    private var markAsReadPill: some View {
        Button {
            timelineContext.send(viewAction: .markAllAsRead)
            dismissMarkAsReadPill()
        } label: {
            markAsReadPillLabel
        }
    }
    
    @ViewBuilder
    private var markAsReadPillLabel: some View {
        // Font scales with Dynamic Type via the Compound token; padding is a fixed point value
        // so the pill grows with the text instead of growing twice over.
        let label = Label {
            Text(L10n.screenRoomlistMarkAsRead)
        } icon: {
            CompoundIcon(\.markAsRead, size: .medium, relativeTo: .compound.bodyLG)
        }
        .font(.compound.bodyLG)
        .foregroundStyle(.compound.textPrimary)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        if #available(iOS 26, *) {
            label.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            label.background(.regularMaterial, in: Capsule())
        }
    }
    
    private func revealMarkAsReadPill(source: MarkAsReadSource) {
        markAsReadSource = source
    }
    
    private func dismissMarkAsReadPill() {
        markAsReadSource = nil
    }
    
    /// Whether the scroll button that the pill is anchored to is still being rendered.
    /// Used to dismiss an orphaned pill when the source button gets hidden — without
    /// this, the pill can render alongside an invisible button. Returns `true` when no
    /// pill is shown so the `onChange` doesn't fire spuriously when the source clears.
    private var pillSourceButtonIsVisible: Bool {
        switch markAsReadSource {
        case .up: timelineContext.viewState.shouldShowJumpToReadMarker
        case .down: timelineContext.viewState.shouldShowScrollToBottomButton
        case .none: true
        }
    }
    
    @ViewBuilder
    private var composer: some View {
        if context.viewState.hasSuccessor {
            tombstonedDialogue
        } else if context.viewState.canSendMessage, !ProcessInfo.isRunningAccessibilityTests {
            // We are not sure why but when wrapped in the room screen the composer toolbar breaks the accessibility tests
            composerToolbar
        } else {
            ComposerDisabledView()
        }
    }
    
    // AGENT-PLATFORM (question 357): they go with the composer they belong to.
    @ViewBuilder
    private var composerSuggestions: some View {
        if !context.viewState.hasSuccessor, context.viewState.canSendMessage, !ProcessInfo.isRunningAccessibilityTests, !isMessageSelectionActive {
            composerToolbar.floatingSuggestions
        }
    }
    
    private var tombstonedDialogue: some View {
        VStack(spacing: 16) {
            Text(L10n.screenRoomTimelineTombstonedRoomMessage)
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textPrimary)
            
            Button {
                context.send(viewAction: .displaySuccessorRoom)
            } label: {
                Text(L10n.screenRoomTimelineTombstonedRoomAction)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.compound(.primary, size: .medium))
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .highlight(gradient: .compound.info, borderColor: .compound.borderInfoSubtle)
    }
    
    @ViewBuilder
    private var loadingIndicator: some View {
        if timelineContext.viewState.showLoading {
            let spinner = ProgressView()
                .progressViewStyle(.circular)
                .tint(.compound.textPrimary)
                .padding(16)
            if #available(iOS 26, *) { // AGENT-PLATFORM (Brief 0083, decision 346)
                spinner.snapshotableGlassEffect(.regular,
                                                snapshotBackground: .compound.bgSubtleSecondary,
                                                in: RoundedRectangle(cornerRadius: SpiralRadius.block, style: .continuous))
            } else {
                spinner
                    .background(.ultraThickMaterial)
                    // swiftlint:disable:next spiral_raw_corner_radius - predates the rule
                    .cornerRadius(8)
            }
        }
    }
    
    private var isMessageSelectionActive: Bool {
        timelineContext.viewState.messageSelection.isActive
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // .principal + .primaryAction works better than .navigation leading + trailing
        // as the latter disables interaction in the action button for rooms with long names
        ToolbarItem(placement: .principal) {
            RoomHeaderView(roomName: context.viewState.roomTitle,
                           roomSubtitle: context.viewState.headerSubtitle, // AGENT-PLATFORM (Brief 0083, question 392)
                           roomAvatar: context.viewState.roomAvatar,
                           dmRecipientDetails: context.viewState.dmRecipientDetails,
                           roomHistorySharingState: context.viewState.roomHistorySharingState,
                           typing: timelineContext.viewState.headerTyping, // AGENT-PLATFORM (Brief 0083, question 359)
                           isCapsule: true, // AGENT-PLATFORM (Brief 0083, decision 344)
                           mediaProvider: context.mediaProvider) {
                context.send(viewAction: .displayRoomDetails)
            }
            .disabled(isMessageSelectionActive) // The room details would cover the selection.
            .onChatBackground() // AGENT-PLATFORM (Brief 0083, question 359)
        }
        
        if isMessageSelectionActive {
            TimelineMessageSelectionToolbar {
                timelineContext.send(viewAction: .clearMessageSelection)
            }
        } else {
            roomActions
        }
    }
    
    @ToolbarContentBuilder
    private var roomActions: some ToolbarContent {
        if !ProcessInfo.processInfo.isiOSAppOnMac || context.viewState.isNativeCallingEnabled {
            if context.viewState.shouldShowCallButton {
                RoomCallControlsToolbar(viewState: context.viewState) { isVoiceCall in
                    context.send(viewAction: .displayCall(isVoiceCall: isVoiceCall))
                }
            }
        }
        // AGENT-PLATFORM (Brief 0083, decision 344): Threads left the header. Its list opens from the profile's row.
    }
}

// MARK: - Previews

struct RoomScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083): Spiral's gates
    static let viewModels = makeViewModels()
    static let readOnlyViewModels = makeViewModels(canSendMessage: false)
    static let tombstonedViewModels = makeViewModels(hasSuccessor: true)
    static let selectingViewModels = makeViewModels(isSelecting: true)
    static let composerViewModel = ComposerToolbarViewModel.mock()
    static let assistantDMViewModels = makeAssistantDMViewModels() // AGENT-PLATFORM (Brief 0083)
    static let dmWithPresenceViewModels = makeDMWithPresenceViewModels() // AGENT-PLATFORM (Brief 0083)
    static let groupWithAgentViewModels = makeGroupWithAgentViewModels() // AGENT-PLATFORM (Brief 0083, decision 357)
    
    static var previews: some View {
        ElementNavigationStack {
            RoomScreen(context: viewModels.room.context,
                       timelineContext: viewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: composerViewModel.context))
        }
        .previewDisplayName("Normal")
        
        ElementNavigationStack {
            RoomScreen(context: readOnlyViewModels.room.context,
                       timelineContext: readOnlyViewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: composerViewModel.context))
        }
        .previewDisplayName("Read-only")
        .snapshotPreferences(expect: readOnlyViewModels.room.context.$viewState.map { !$0.canSendMessage })
        
        ElementNavigationStack {
            RoomScreen(context: tombstonedViewModels.room.context,
                       timelineContext: tombstonedViewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: composerViewModel.context))
        }
        .previewDisplayName("Tombstoned")
        .snapshotPreferences(expect: tombstonedViewModels.room.context.$viewState.map(\.hasSuccessor))
        
        ElementNavigationStack {
            RoomScreen(context: selectingViewModels.room.context,
                       timelineContext: selectingViewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: composerViewModel.context))
        }
        .previewDisplayName("Selecting")
        .snapshotPreferences(expect: selectingViewModels.timeline.context.$viewState.map(\.messageSelection.isActive))
        
        // AGENT-PLATFORM (Brief 0083): the assistant's DM, the room on the reviewer's path.
        ElementNavigationStack {
            RoomScreen(context: assistantDMViewModels.room.context,
                       timelineContext: assistantDMViewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: composerViewModel.context))
        }
        .previewDisplayName("Assistant DM")
        
        // AGENT-PLATFORM (Brief 0083): a person's DM, so the audit reaches the header's subtitle (their presence).
        ElementNavigationStack {
            RoomScreen(context: dmWithPresenceViewModels.room.context,
                       timelineContext: dmWithPresenceViewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: composerViewModel.context))
        }
        .previewDisplayName("DM with presence")
        .snapshotPreferences(expect: dmWithPresenceViewModels.room.context.$viewState.map { $0.dmRecipientDetails.presence != nil })
        
        // AGENT-PLATFORM (Brief 0083, decision 357)
        ElementNavigationStack {
            RoomScreen(context: groupWithAgentViewModels.room.context,
                       timelineContext: groupWithAgentViewModels.timeline.context,
                       composerToolbar: ComposerToolbar(context: composerViewModel.context))
        }
        .previewDisplayName("Group with an agent")
    }
    
    static func makeViewModels(canSendMessage: Bool = true, hasSuccessor: Bool = false, isSelecting: Bool = false) -> ViewModels {
        let roomProxyMock = JoinedRoomProxyMock(.init(id: "stable_id",
                                                      name: "Preview room",
                                                      hasOngoingCall: true,
                                                      successor: hasSuccessor ? .init(roomId: UUID().uuidString, reason: nil) : nil,
                                                      powerLevelsConfiguration: .init(canUserSendMessage: canSendMessage)))
        let roomViewModel = RoomScreenViewModel.mock(roomProxyMock: roomProxyMock)
        
        let timelineController = TimelineControllerMock(.init())
        let timelineViewModel = TimelineViewModel(roomProxy: roomProxyMock,
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
            let eventIDs = timelineController.timelineItems.compactMap { ($0 as? EventBasedTimelineItemProtocol)?.id.eventID }
            timelineViewModel.state.messageSelection.isActive = true
            timelineViewModel.state.messageSelection.selectedEventIDs = Set(eventIDs.prefix(2))
        }
        
        return .init(room: roomViewModel, timeline: timelineViewModel)
    }
    
    struct ViewModels {
        let room: RoomScreenViewModelProtocol
        let timeline: TimelineViewModelProtocol
    }
}

// AGENT-PLATFORM (Brief 0083): the call bar over the room joins Spiral's gates with decision 307's green fill
// (phase 3): its white read 2.48:1 on #4DB87E in dark (contrast triage, cause E), 4.50:1 on #2D8659.
struct RoomScreenMinimizedCall_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    // AGENT-PLATFORM (Brief 0063, G9): a live call to sit above the room in
    // the production-composition preview below.
    static let minimizedCallViewModel = NativeCallScreen_Previews.makeAgentViewModel()
    
    static var previews: some View {
        // AGENT-PLATFORM (Brief 0063, G9): the PRODUCTION composition — the
        // minimized call bar stacked above a whole room, the way
        // `NavigationTabCoordinator` lays the two out.
        //
        // This preview exists because its absence is what let the bar ship on
        // top of the room's header twice. The bar had a preview and the room
        // had a preview; neither could show the one thing that was wrong,
        // which was how they sit TOGETHER. What this snapshot must prove is
        // that the room's own navigation bar — its title and back button —
        // is fully visible below the green, not behind it.
        VStack(spacing: 0) {
            NativeCallBar(context: minimizedCallViewModel.context)
            
            ElementNavigationStack {
                RoomScreen(context: RoomScreen_Previews.viewModels.room.context,
                           timelineContext: RoomScreen_Previews.viewModels.timeline.context,
                           composerToolbar: ComposerToolbar(context: RoomScreen_Previews.composerViewModel.context))
            }
        }
        .previewDisplayName("Minimized call over room")
    }
}
