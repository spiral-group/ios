//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import SwiftUI
import Testing

/// The page on screen is the media the bars act on, in either layout direction. A right-to-left flow layout mirrors
/// its items but not its content offset, so a pager that turns offsets into indices by arithmetic shows one photo
/// while Delete, Forward and the count act on another.
@MainActor
struct MediaViewerPagerTests {
    @Test(arguments: [UITraitEnvironmentLayoutDirection.leftToRight, .rightToLeft])
    func theViewerOpensOnTheMediaItWasOpenedOn(_ direction: UITraitEnvironmentLayoutDirection) async throws {
        for initialIndex in 0..<3 {
            let viewer = try await Viewer(initialItemIndex: initialIndex, direction: direction)
            let items = viewer.context.viewState.dataSource.previewItems

            #expect(viewer.pageOnScreen == .media(items[initialIndex].id),
                    "\(direction == .rightToLeft ? "RTL" : "LTR"): opened on item \(initialIndex), \(viewer.diagnostics)")
            #expect(viewer.context.viewState.dataSource.currentPage == .media(items[initialIndex].id))
        }
    }

    @Test(arguments: [UITraitEnvironmentLayoutDirection.leftToRight, .rightToLeft])
    func aSwipeMakesThePageOnScreenTheCurrentMedia(_ direction: UITraitEnvironmentLayoutDirection) async throws {
        // Given a viewer on the middle item, which sits in the middle either way.
        let viewer = try await Viewer(initialItemIndex: 1, direction: direction)
        let items = viewer.context.viewState.dataSource.previewItems

        // When the pager comes to rest on the last item, wherever the layout put it.
        try viewer.swipe(toItem: 2)
        await waitUntil { viewer.context.viewState.dataSource.currentPage == .media(items[2].id) }

        // Then it is the one on screen and the one the bars act on.
        #expect(viewer.pageOnScreen == .media(items[2].id), "\(viewer.diagnostics)")
        #expect(viewer.context.viewState.dataSource.currentPage == .media(items[2].id))
    }

    @Test
    func inRightToLeftTheNextMediaComesFromTheLeft() async throws {
        let viewer = try await Viewer(initialItemIndex: 0, direction: .rightToLeft)
        let first = try viewer.frame(ofItem: 0)
        let second = try viewer.frame(ofItem: 1)
        #expect(second.minX < first.minX)
    }

    /// Polls for up to 2 s: the view model loads in unstructured tasks.
    private func waitUntil(_ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(2)
        while !condition(), Date() < end {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// A media viewer on screen, over three media and no more to load, laid out in the given direction.
@MainActor
private final class Viewer {
    let viewModel: TimelineMediaPreviewViewModel
    let controller: MediaViewerController
    let window: UIWindow
    let collectionView: UICollectionView

    var context: TimelineMediaPreviewViewModel.Context {
        viewModel.context
    }

    init(initialItemIndex: Int, direction: UITraitEnvironmentLayoutDirection) async throws {
        let items = Self.makeItems()
        let timelineController = TimelineControllerMock(.init(timelineKind: .media(.mediaFilesScreen),
                                                              timelineItems: items,
                                                              paginationState: .init(backward: .endReached, forward: .endReached)))
        viewModel = TimelineMediaPreviewViewModel(initialItem: items[initialItemIndex],
                                                  timelineViewModel: TimelineViewModel.mock(timelineKind: .media(.mediaFilesScreen),
                                                                                            timelineController: timelineController),
                                                  mediaProvider: MediaProviderMock(.init()),
                                                  photoLibraryManager: PhotoLibraryManagerMock(.init()),
                                                  userIndicatorController: UserIndicatorControllerMock(),
                                                  appMediator: AppMediatorMock())
        controller = MediaViewerController(context: viewModel.context)
        controller.traitOverrides.layoutDirection = direction

        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.isHidden = false
        window.layoutIfNeeded()
        collectionView = try #require(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
        try? await Task.sleep(for: .milliseconds(50))
        window.layoutIfNeeded()
    }

    private var pagesDataSource: UICollectionViewDiffableDataSource<Int, TimelineMediaPreviewPage>? {
        collectionView.dataSource as? UICollectionViewDiffableDataSource<Int, TimelineMediaPreviewPage>
    }

    /// The page of the cell that fills the screen.
    var pageOnScreen: TimelineMediaPreviewPage? {
        let centre = CGPoint(x: collectionView.contentOffset.x + controller.view.bounds.width / 2, y: collectionView.bounds.midY)
        guard let indexPath = collectionView.indexPathForItem(at: centre) else { return nil }
        return (collectionView.cellForItem(at: indexPath) as? MediaViewerPageCell)?.page
    }

    var diagnostics: String {
        "offset \(collectionView.contentOffset.x) of \(collectionView.contentSize.width), showing \(pageOnScreen.map { "\($0)" } ?? "nothing")"
    }

    /// Where the page of the timeline's `item` sits in the pager.
    func frame(ofItem item: Int) throws -> CGRect {
        let page = TimelineMediaPreviewPage.media(context.viewState.dataSource.previewItems[item].id)
        let indexPath = try #require(pagesDataSource?.indexPath(for: page))
        return try #require(collectionView.layoutAttributesForItem(at: indexPath)).frame
    }

    /// Brings the pager to rest on the page of the timeline's `item` the way a swipe does.
    func swipe(toItem item: Int) throws {
        collectionView.contentOffset = try CGPoint(x: frame(ofItem: item).minX, y: 0)
        window.layoutIfNeeded()
        controller.scrollViewDidEndDecelerating(collectionView)
    }

    private static func makeItems() -> [EventBasedMessageTimelineItemProtocol] {
        ["First.jpeg", "Second.jpeg", "Third.jpeg"].map { filename in
            ImageRoomTimelineItem(id: .randomEvent,
                                  timestamp: .mock,
                                  isOutgoing: false,
                                  isEditable: false,
                                  canBeRepliedTo: true,
                                  sender: .init(id: ""),
                                  content: .init(filename: filename,
                                                 imageInfo: .mockImage,
                                                 thumbnailInfo: .mockThumbnail,
                                                 contentType: .jpeg))
        }
    }
}
