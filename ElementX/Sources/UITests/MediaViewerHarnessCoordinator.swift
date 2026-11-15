//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 398): the media viewer on a real image,
// for the UI test that checks the viewer's bars hold close, share and info.
//

import SwiftUI

class MediaViewerHarnessCoordinator: CoordinatorProtocol {
    func toPresentable() -> AnyView {
        AnyView(MediaViewerHarness())
    }
}

private struct MediaViewerHarness: View {
    @State private var viewModel: TimelineMediaPreviewViewModel?

    var body: some View {
        Color.clear
            .timelineMediaPreview(viewModel: $viewModel)
            .onAppear { viewModel = Self.makeViewModel() }
    }

    private static func makeViewModel() -> TimelineMediaPreviewViewModel {
        let item = ImageRoomTimelineItem(id: .randomEvent,
                                         timestamp: .mock,
                                         isOutgoing: false,
                                         isEditable: false,
                                         canBeRepliedTo: true,
                                         sender: .init(id: "@alex:example.org", displayName: "Alex Sample"),
                                         content: .init(filename: "Garden.jpeg",
                                                        caption: "First frost this morning.",
                                                        imageInfo: .mockImage,
                                                        thumbnailInfo: .mockThumbnail,
                                                        contentType: .jpeg))
        let timelineKind = TimelineKind.media(.roomScreenLive)
        let timelineController = TimelineControllerMock(.init(timelineKind: timelineKind, timelineItems: [item]))

        return TimelineMediaPreviewViewModel(initialItem: item,
                                             timelineViewModel: TimelineViewModel.mock(timelineKind: timelineKind,
                                                                                       timelineController: timelineController),
                                             mediaProvider: MediaProviderMock(.init()),
                                             photoLibraryManager: PhotoLibraryManagerMock(.init()),
                                             userIndicatorController: UserIndicatorControllerMock(),
                                             appMediator: AppMediatorMock())
    }
}
