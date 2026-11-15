//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct HomeScreen: View {
    @ObservedObject var context: HomeScreenViewModel.Context
    // AGENT-PLATFORM (Brief 0083, question 343): the search field and its results live here, not on a tab.
    var searchContext: SearchScreenViewModelType.Context?
    
    @State private var scrollViewAdapter = ScrollViewAdapter()
    
    @Namespace private var navigationTransitionNamespace
    private enum NavigationTransitionSourceID {
        case spaceFilters
    }
    
    var body: some View {
        content
            .alert(item: $context.alertInfo)
            .alert(item: $context.leaveRoomAlertItem,
                   actions: leaveRoomAlertActions,
                   message: leaveRoomAlertMessage)
            .navigationTitle(title)
            // AGENT-PLATFORM (Brief 0083, question 343): a small centred title; this replaces 310's large one.
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            // AGENT-PLATFORM (Brief 0083, question 343): no `.editor` role: it puts the title beside the leading button.
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .track(screen: .Home)
            // AGENT-PLATFORM (Brief 0083, decision 308): no bloom behind the bar on the reviewer's path.
            // AGENT-PLATFORM (Brief 0078): upstream's `.sentryTrace` went with Sentry.
            .sheet(item: $context.spaceFiltersViewModel) { vm in
                ChatsSpaceFiltersScreen(context: vm.context)
                    .navigationTransition(.zoom(sourceID: NavigationTransitionSourceID.spaceFilters,
                                                in: navigationTransitionNamespace))
            }
            .sheet(isPresented: $context.isPresentingMultiAccountAnnouncement) {
                MultiAccountAnnouncementView(context: context)
                    .onAppear { context.send(viewAction: .multiAccountAnnouncementAppeared) }
            }
            .onAppear { context.send(viewAction: .screenAppeared) }
    }
    
    // MARK: - Private
    
    // AGENT-PLATFORM (Brief 0083, question 343)
    @ViewBuilder
    private var content: some View {
        if let searchContext {
            SearchScreen(context: searchContext) {
                HomeScreenContent(context: context, scrollViewAdapter: scrollViewAdapter)
            }
        } else {
            HomeScreenContent(context: context, scrollViewAdapter: scrollViewAdapter)
        }
    }
    
    private var title: String {
        if let selectedSpace = context.viewState.selectedSpaceFilter {
            selectedSpace.room.name
        } else {
            L10n.screenRoomlistMainSpaceTitle
        }
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // AGENT-PLATFORM (Brief 0083, question 343): the filter menu leads, to balance Start chat around the centred
        // title, while the list shows rooms.
        if context.viewState.shouldShowFilters {
            ToolbarItem(placement: .topBarLeading) {
                RoomListFiltersMenuButton(state: $context.filtersState)
            }
        }
        
        // AGENT-PLATFORM (Brief 0083, decision 308): iOS 18 keeps the plain bar button, not Compound's super style.
        ToolbarItem(placement: .primaryAction) {
            newRoomButton
        }
        
        if context.viewState.shouldShowSpaceFilters {
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            
            ToolbarItem(placement: .primaryAction) {
                SpaceFiltersButton(selected: context.viewState.selectedSpaceFilter != nil) {
                    context.send(viewAction: .spaceFilters)
                }
                .matchedTransitionSource(id: NavigationTransitionSourceID.spaceFilters,
                                         in: navigationTransitionNamespace)
            }
        }
    }
    
    @ViewBuilder
    private var newRoomButton: some View {
        switch context.viewState.roomListMode {
        case .empty, .rooms:
            Button {
                context.send(viewAction: .startChat)
            } label: {
                CompoundIcon(\.plus)
            }
            .accessibilityLabel(L10n.actionStartChat)
            .accessibilityIdentifier(A11yIdentifiers.homeScreen.startChat)
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func leaveRoomAlertActions(_ item: LeaveRoomAlertItem) -> some View {
        Button(item.cancelTitle, role: .cancel) { }
        Button(item.confirmationTitle, role: .destructive) {
            context.send(viewAction: .confirmLeaveRoom(roomIdentifier: item.roomID))
        }
    }
    
    private func leaveRoomAlertMessage(_ item: LeaveRoomAlertItem) -> some View {
        Text(item.subtitle)
    }
    
    private struct SpaceFiltersButton: View {
        @Environment(\.isInSidebar) private var isInSidebar
        
        var selected = false
        var action: () -> Void
        
        /// Design prefers the custom style over the system's styling of a Toggle within a toolbar,
        /// however Glass isn't supported for toolbar buttons in the sidebar on iPadOS 26 (likely due
        /// to glass on glass being discouraged by Apple), so we need to handle our styling accordingly.
        var shouldUseGlassButtonStyle: Bool {
            !isInSidebar
        }
        
        var body: some View {
            if #available(iOS 26, *), shouldUseGlassButtonStyle {
                if selected {
                    content
                        .backportButtonStyleGlassProminent()
                        .tint(.compound.bgActionPrimaryRest)
                } else {
                    content
                }
            } else {
                if selected {
                    content
                        .buttonStyle(.compound(.primary, size: .toolbarIcon))
                } else {
                    content
                        .buttonStyle(.compound(.tertiary, size: .toolbarIcon))
                }
            }
        }
        
        private var content: some View {
            Button {
                action()
            } label: {
                CompoundIcon(\.filter)
            }
            .accessibilityLabel(L10n.screenRoomlistYourSpaces)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(A11yIdentifiers.homeScreen.spaceFilters)
        }
    }
}

// MARK: - Previews

struct HomeScreen_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let loadingViewModel = viewModel(.skeletons)
    static let emptyViewModel = viewModel(.empty)
    static let loadedViewModel = viewModel(.rooms)
    // AGENT-PLATFORM (Brief 0083): Chats with a filter on. The mock keeps the direct chats for People.
    static let filteredViewModel = {
        let model = viewModel(.rooms)
        model.context.filtersState.activateFilter(.people)
        return model
    }()

    static var previews: some View {
        ElementNavigationStack {
            HomeScreen(context: loadingViewModel.context)
        }
        .snapshotPreferences(expect: loadingViewModel.context.$viewState.map { state in
            state.roomListMode == .skeletons
        })
        .environment(\.spiralPreloaderDelay, .zero) // AGENT-PLATFORM (Brief 0083): shows what a slow load shows.
        .previewDisplayName("Loading")
        
        ElementNavigationStack {
            HomeScreen(context: emptyViewModel.context)
        }
        .snapshotPreferences(expect: emptyViewModel.context.$viewState.map { state in
            state.roomListMode == .empty
        })
        .previewDisplayName("Empty")
        
        ElementNavigationStack {
            HomeScreen(context: loadedViewModel.context)
        }
        .snapshotPreferences(expect: loadedViewModel.context.$viewState.map { state in
            state.roomListMode == .rooms
        })
        .previewDisplayName("Loaded")

        // AGENT-PLATFORM (Brief 0083): the filters' active state.
        ElementNavigationStack {
            HomeScreen(context: filteredViewModel.context)
        }
        .snapshotPreferences(expect: filteredViewModel.context.$viewState.map { state in
            state.roomListMode == .rooms && !state.rooms.isEmpty && state.rooms.allSatisfy(\.isDirect)
        })
        .previewDisplayName("Filtered")
    }
    
    static func viewModel(_ mode: HomeScreenRoomListMode) -> HomeScreenViewModel {
        let userID = "@alice:example.com"
        
        let roomSummaryProviderState: RoomSummaryProviderMockConfigurationState = switch mode {
        case .awaitingCachedRooms, .skeletons:
            .loading
        case .empty:
            .loaded([])
        case .rooms:
            .loaded(.mockRooms)
        }
        
        let clientProxy = ClientProxyMock(.init(userID: userID,
                                                roomSummaryProvider: RoomSummaryProviderMock(.init(state: roomSummaryProviderState))))
        
        let userSession = UserSessionMock(.init(clientProxy: clientProxy))
        
        return HomeScreenViewModel(userSession: userSession,
                                   availableSessionsPublisher: .init([.init(userSession: userSession)]),
                                   selectedRoomPublisher: CurrentValueSubject<String?, Never>(nil).asCurrentValuePublisher(),
                                   analyticsService: AnalyticsServiceMock(.init()),
                                   bugReportService: BugReportServiceMock(.init()),
                                   userIndicatorController: UserIndicatorControllerMock())
    }
}
