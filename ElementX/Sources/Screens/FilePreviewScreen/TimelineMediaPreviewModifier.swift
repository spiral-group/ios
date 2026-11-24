//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

extension View {
    /// Shows the timeline's media in Spiral's own viewer, faded in over everything else. AGENT-PLATFORM
    /// (Brief 0083, question 413): replaces QuickLook, whose bars Element had to re-place every 0.1 s.
    func timelineMediaPreview(viewModel: Binding<TimelineMediaPreviewViewModel?>) -> some View {
        background {
            MediaViewerPresenter(viewModel: viewModel)
                .accessibilityHidden(true)
        }
    }
}

/// Presents the viewer over the whole screen from UIKit, and takes it away when the binding is cleared from outside
/// (forward, reply, delete).
private struct MediaViewerPresenter: UIViewControllerRepresentable {
    @Binding var viewModel: TimelineMediaPreviewViewModel?

    func makeUIViewController(context: Context) -> MediaViewerPresentingController {
        MediaViewerPresentingController()
    }

    func updateUIViewController(_ controller: MediaViewerPresentingController, context: Context) {
        controller.onDismissed = { viewModel = nil }
        controller.show(viewModel)
    }

    /// The screen under the viewer is going away: take the viewer with it, so nothing is left covering the app.
    static func dismantleUIViewController(_ controller: MediaViewerPresentingController, coordinator: ()) {
        controller.show(nil)
    }
}

final class MediaViewerPresentingController: UIViewController {
    var onDismissed: () -> Void = { }
    private weak var viewer: MediaViewerController?
    private var shownViewModelID: UUID?
    /// A viewer asked for before this screen reached a window, shown once it has.
    private var pendingViewModel: TimelineMediaPreviewViewModel?
    private var callObserver: AnyCancellable?

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        // AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): the viewer is above the whole window, the call
        // screen too: it goes as a call comes up.
        callObserver = NotificationCenter.default.publisher(for: .callScreenWillCoverTheApp)
            .sink { [weak self] _ in
                self?.pendingViewModel = nil // nor does a viewer still waiting for its window come up over the call
                self?.viewer?.closeAtOnce()
            }
    }

    /// Shows the viewer for `viewModel`, or closes it for `nil`. The viewer closes only once, whoever asks.
    func show(_ viewModel: TimelineMediaPreviewViewModel?) {
        guard let viewModel else {
            pendingViewModel = nil
            viewer?.close()
            return
        }
        guard viewModel.instanceID != shownViewModelID, viewer == nil else { return }
        // A screen that opens on its media sets the view model before it is in a window, and then nothing asks again.
        guard let presenter = topmostPresenter else {
            pendingViewModel = viewModel
            return
        }
        pendingViewModel = nil
        shownViewModelID = viewModel.instanceID

        let viewer = MediaViewerController(context: viewModel.context)
        viewer.onDismissed = { [weak self] in
            self?.shownViewModelID = nil
            self?.onDismissed()
        }
        self.viewer = viewer
        MediaViewerFrameProbe.begin(.open)
        KeyboardDismissal.endEditing() // AGENT-PLATFORM (1.0.3): over full screen, the composer under it would keep the keyboard
        presenter.present(viewer, animated: false) // The viewer fades itself in.
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let pendingViewModel {
            show(pendingViewModel)
        }
    }

    /// The controller on top of this screen's window, which is the one able to present.
    private var topmostPresenter: UIViewController? {
        var presenter = view.window?.rootViewController
        while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }
        return presenter
    }
}

// MARK: - Previews

struct TimelineMediaPreviewModifier_Previews: PreviewProvider {
    static let viewModel = makeViewModel()
    static let downloadingViewModel = makeViewModel(isDownloading: true)
    static let downloadErrorViewModel = makeViewModel(isDownloadError: true)

    static var previews: some View {
        MediaViewerPreview(viewModel: viewModel)
            .previewDisplayName("Normal")
        MediaViewerPreview(viewModel: downloadingViewModel)
            .previewDisplayName("Downloading")
        MediaViewerPreview(viewModel: downloadErrorViewModel)
            .previewDisplayName("Download Error")
    }

    static func makeViewModel(isDownloading: Bool = false, isDownloadError: Bool = false) -> TimelineMediaPreviewViewModel {
        let item = FileRoomTimelineItem(id: .randomEvent,
                                        timestamp: .mock,
                                        isOutgoing: false,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: .init(id: "", displayName: "Sally Sanderson"),
                                        content: .init(filename: "Important document.pdf",
                                                       caption: "A caption goes right here.",
                                                       source: try? .init(url: .mockMXCFile, mimeType: nil),
                                                       fileSize: 3 * 1024 * 1024,
                                                       thumbnailSource: nil,
                                                       contentType: .pdf))

        let timelineController = TimelineControllerMock(.init(timelineKind: .media(.mediaFilesScreen), timelineItems: [item]))

        let mediaProvider = MediaProviderMock(.init())

        if isDownloading {
            mediaProvider.loadFileFromSourceFilenameClosure = { _, _ in
                try? await Task.sleep(for: .seconds(3600))
                return .failure(.failedRetrievingFile)
            }
        } else if isDownloadError {
            mediaProvider.loadFileFromSourceFilenameClosure = { _, _ in .failure(.failedRetrievingFile) }
        }

        return TimelineMediaPreviewViewModel(initialItem: item,
                                             timelineViewModel: TimelineViewModel.mock(timelineKind: timelineController.timelineKind,
                                                                                       timelineController: timelineController),
                                             mediaProvider: mediaProvider,
                                             photoLibraryManager: PhotoLibraryManagerMock(.init()),
                                             userIndicatorController: UserIndicatorControllerMock(),
                                             appMediator: AppMediatorMock())
    }
}

private struct MediaViewerPreview: UIViewControllerRepresentable {
    let viewModel: TimelineMediaPreviewViewModel

    func makeUIViewController(context: Context) -> MediaViewerController {
        MediaViewerController(context: viewModel.context)
    }

    func updateUIViewController(_ controller: MediaViewerController, context: Context) { }
}
