//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import Testing

@MainActor
struct MediaEventsTimelineScreenViewModelTests {
    @Test
    func changingScreenModeSwitchesTimelines() {
        let mediaTimelineViewModel = makeTimelineViewModel(allowedGalleryItemTypes: [.image, .video])
        let filesTimelineViewModel = makeTimelineViewModel(allowedGalleryItemTypes: [.file, .audio])
        
        let viewModel = MediaEventsTimelineScreenViewModel(mediaTimelineViewModel: mediaTimelineViewModel,
                                                           filesTimelineViewModel: filesTimelineViewModel,
                                                           mediaProvider: MediaProviderMock(.init()),
                                                           userIndicatorController: UserIndicatorControllerMock(),
                                                           appMediator: AppMediatorMock(.init()))
        let context = viewModel.context
        
        // Initially the media timeline is active, showing only images and videos.
        #expect(context.viewState.screenMode == .media)
        #expect(context.viewState.activeTimelineContext === mediaTimelineViewModel.context)
        #expect(allItemsMatchScreenMode(.media, groups: context.viewState.groups))
        
        // When switching the mode, the files timeline becomes active,
        // showing only files, audio and voice messages.
        context.send(viewAction: .changeScreenMode(.files))
        
        #expect(context.viewState.screenMode == .files)
        #expect(context.viewState.activeTimelineContext === filesTimelineViewModel.context)
        #expect(allItemsMatchScreenMode(.files, groups: context.viewState.groups))
        
        // And switching back restores the media timeline.
        context.send(viewAction: .changeScreenMode(.media))
        
        #expect(context.viewState.screenMode == .media)
        #expect(context.viewState.activeTimelineContext === mediaTimelineViewModel.context)
        #expect(allItemsMatchScreenMode(.media, groups: context.viewState.groups))
    }
    
    // MARK: - Failed reads (AGENT-PLATFORM, 1.0.3 B14)
    
    @Test
    func failedPageOffersRetryAndWaitsForIt() async throws {
        let mediaTimelineController = TimelineControllerMock.failingMediaGallery
        let viewModel = makeViewModel(mediaTimelineController: mediaTimelineController)
        let context = viewModel.context
        
        context.send(viewAction: .oldestItemDidAppear)
        try await waitUntil { context.viewState.hasFailedToLoad }
        
        // The SDK's state is idle again and the oldest item shows again, but a failed page doesn't read again by itself.
        context.send(viewAction: .oldestItemDidDisappear)
        context.send(viewAction: .oldestItemDidAppear)
        try await Task.sleep(for: .milliseconds(200))
        #expect(mediaTimelineController.paginateBackwardsRequestSizeCallsCount == 1)
        #expect(context.viewState.hasFailedToLoad)
        #expect(!context.viewState.shouldShowEmptyState)
        withExtendedLifetime(viewModel) { }
    }
    
    @Test
    func retryReadsAgainAndSuccessClearsTheFailure() async throws {
        let mediaTimelineController = TimelineControllerMock.failingMediaGallery
        let viewModel = makeViewModel(mediaTimelineController: mediaTimelineController)
        let context = viewModel.context
        context.send(viewAction: .oldestItemDidAppear)
        try await waitUntil { context.viewState.hasFailedToLoad }
        
        mediaTimelineController.paginateBackwardsRequestSizeReturnValue = .success(())
        context.send(viewAction: .retry)
        
        try await waitUntil { mediaTimelineController.paginateBackwardsRequestSizeCallsCount == 2 }
        try await Task.sleep(for: .milliseconds(200))
        #expect(!context.viewState.hasFailedToLoad)
        withExtendedLifetime(viewModel) { }
    }
    
    @Test
    func retryThatFailsAgainStaysFailed() async throws {
        let mediaTimelineController = TimelineControllerMock.failingMediaGallery
        let viewModel = makeViewModel(mediaTimelineController: mediaTimelineController)
        let context = viewModel.context
        context.send(viewAction: .oldestItemDidAppear)
        try await waitUntil { context.viewState.hasFailedToLoad }
        
        context.send(viewAction: .retry)
        
        try await waitUntil { mediaTimelineController.paginateBackwardsRequestSizeCallsCount == 2 }
        try await waitUntil { context.viewState.hasFailedToLoad }
        context.send(viewAction: .oldestItemDidDisappear)
        context.send(viewAction: .oldestItemDidAppear)
        try await Task.sleep(for: .milliseconds(200))
        #expect(mediaTimelineController.paginateBackwardsRequestSizeCallsCount == 2)
        withExtendedLifetime(viewModel) { }
    }
    
    // MARK: - Helpers
    
    private func makeViewModel(mediaTimelineController: TimelineControllerMock) -> MediaEventsTimelineScreenViewModel {
        MediaEventsTimelineScreenViewModel(mediaTimelineViewModel: TimelineViewModel.mock(timelineKind: .media(.mediaFilesScreen),
                                                                                          timelineController: mediaTimelineController),
                                           filesTimelineViewModel: makeTimelineViewModel(allowedGalleryItemTypes: [.file, .audio]),
                                           mediaProvider: MediaProviderMock(.init()),
                                           userIndicatorController: UserIndicatorControllerMock(),
                                           appMediator: AppMediatorMock(.init()))
    }
    
    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(5)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    
    // Both timelines are given the same mixed chunk of items, filtered as they are in the app, so that
    // the filtering of the items is what's under test.
    private func makeTimelineViewModel(allowedGalleryItemTypes: [TimelineAllowedGalleryItemType]) -> TimelineViewModel {
        let timelineController = TimelineControllerMock(.init(timelineKind: .media(.mediaFilesScreen),
                                                              timelineItems: [TimelineFixtures.separator] + TimelineFixtures.mediaChunk,
                                                              allowedGalleryItemTypes: allowedGalleryItemTypes))
        return TimelineViewModel.mock(timelineKind: .media(.mediaFilesScreen), timelineController: timelineController)
    }
    
    private func allItemsMatchScreenMode(_ screenMode: MediaEventsTimelineScreenMode, groups: [MediaEventsTimelineGroup]) -> Bool {
        let items = groups.flatMap(\.items)
        guard !items.isEmpty else { return false }
        
        return items.allSatisfy { item in
            switch item.type {
            case .image, .video: screenMode == .media
            case .audio, .file, .voice: screenMode == .files
            default: false
            }
        }
    }
}
