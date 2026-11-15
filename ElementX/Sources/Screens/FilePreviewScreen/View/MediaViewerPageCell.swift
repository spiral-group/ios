//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): one page of Spiral's own viewer — a photo, a video or audio under the
// system's player, a file to open in QuickLook, or the loading page at an end of the loaded media. The picture is
// UIKit and keeps its frame from the first thumbnail to the full photo; only the small centred status is SwiftUI.
//

import Compound
import SpiralTokens
import SwiftUI

final class MediaViewerPageCell: UICollectionViewCell {
    struct Configuration {
        let page: TimelineMediaPreviewPage
        let media: TimelineMediaPreviewItem.Media?
        /// The content scanner's verdict, only ever held for the current item.
        let scanState: TimelineMediaPreviewItem.Scan.State?
        let playback: MediaViewerPlayback?
        let mediaProvider: MediaProviderProtocol?
        let imageLoader: MediaViewerImageLoader
        let openFile: () -> Void
        let play: () -> Void
        /// A pinch or a double tap started zooming the photo.
        let zoomStarted: () -> Void
    }

    /// The empty strip between two pages, on the trailing side of each.
    static let pageSpacing: CGFloat = 16

    private(set) var page: TimelineMediaPreviewPage?
    /// Where the system player sits while this page plays. Empty, it lets touches through to the picture.
    let playerContainer = MediaViewerPassthroughView()

    private let pageView = UIView()
    private let photoView = MediaViewerZoomingScrollView()
    private let statusView: UIView & UIContentView
    private var status: MediaViewerPageStatus = .none
    private var configuration: Configuration?
    /// How sharp the picture on show is, so a blurrier one never replaces it.
    private var quality = Quality.none
    private var thumbnailTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var failedDecoding = false

    private enum Quality: Int, Comparable {
        case none, thumbnail, screen, full

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var isZoomedIn: Bool {
        photoView.isZoomedIn
    }

    /// Whether `view` belongs to the page's own buttons, which a tap toggling the bars must leave alone.
    func ownsControl(_ view: UIView) -> Bool {
        view.isDescendant(of: statusView) && status.isInteractive
    }

    override init(frame: CGRect) {
        statusView = UIHostingConfiguration { MediaViewerPageStatusView(status: .none) }
            .margins(.all, 0)
            .makeContentView()
        super.init(frame: frame)

        contentView.addSubview(pageView)
        pageView.addSubview(photoView)
        pageView.addSubview(playerContainer)
        pageView.addSubview(statusView)

        photoView.onZoomStarted = { [weak self] in
            self?.loadFullPhoto()
            self?.configuration?.zoomStarted()
        }
        statusView.backgroundColor = .clear
        statusView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusView.centerXAnchor.constraint(equalTo: pageView.centerXAnchor),
            statusView.centerYAnchor.constraint(equalTo: pageView.centerYAnchor),
            statusView.widthAnchor.constraint(lessThanOrEqualTo: pageView.widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pageView.frame = CGRect(x: 0, y: 0, width: contentView.bounds.width - Self.pageSpacing, height: contentView.bounds.height)
        photoView.frame = pageView.bounds
        playerContainer.frame = pageView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        page = nil
        configuration = nil
        thumbnailTask?.cancel()
        thumbnailTask = nil
        decodeTask?.cancel()
        decodeTask = nil
        quality = .none
        failedDecoding = false
        photoView.reset()
        setStatus(.none)
    }

    func zoomOut() {
        photoView.zoomOut()
    }

    /// Brings the page in line with its media. Cheap when nothing changed, so it runs on every update.
    func configure(_ configuration: Configuration) {
        if page != configuration.page {
            prepareForReuse()
            page = configuration.page
        }
        self.configuration = configuration
        updateAccessibility(configuration)

        guard case .media = configuration.page, let media = configuration.media else {
            photoView.isHidden = true
            setStatus(.progress(text: nil))
            return
        }

        switch configuration.scanState {
        case .scanning:
            photoView.isHidden = true
            setStatus(.progress(text: L10n.contentScannerScanning))
            return
        case .failure(let failure):
            photoView.isHidden = true
            setStatus(.scanFailure(failure))
            return
        case nil:
            break
        }

        if media.downloadError != nil || failedDecoding {
            photoView.isHidden = true
            setStatus(.downloadError)
            return
        }

        switch media.kind {
        case .image:
            showPhoto(media, configuration: configuration)
            setStatus(media.fileURL == nil ? .progress(text: nil) : .none)
        case .video:
            showPoster(media, configuration: configuration)
            let showsPlayButton = configuration.playback?.showsPlayButton ?? true
            setStatus(showsPlayButton ? .play(isLoading: media.fileURL == nil) : .none)
        case .audio:
            photoView.isHidden = true
            let showsPlayButton = configuration.playback?.showsPlayButton ?? true
            setStatus(showsPlayButton ? .play(isLoading: media.fileURL == nil) : .none)
        case .file:
            photoView.isHidden = true
            setStatus(.file(name: media.filename ?? L10n.commonFile, details: media.fileDetails, canOpen: media.fileURL != nil))
        }
    }

    // MARK: Pictures

    private func showPhoto(_ media: TimelineMediaPreviewItem.Media, configuration: Configuration) {
        photoView.isHidden = false
        photoView.isZoomEnabled = true

        guard let url = media.fileURL else {
            showThumbnail(media, configuration: configuration)
            return
        }
        if let image = configuration.imageLoader.bestCachedImage(for: url) {
            show(image, quality: configuration.imageLoader.cachedImage(for: url, resolution: .full) == nil ? .screen : .full, media: media)
            return
        }
        showThumbnail(media, configuration: configuration)
        guard decodeTask == nil else { return }
        decodeTask = Task { [weak self] in
            let isAnimated = await Task.detached { MediaViewerImageLoader.isAnimated(url: url) }.value
            let image = isAnimated ? nil : await configuration.imageLoader.image(for: url, resolution: .screen)
            guard !Task.isCancelled, let self, page == configuration.page else { return }
            if isAnimated {
                showAnimatedPhoto(url, media: media)
            } else if let image {
                show(image, quality: .screen, media: media)
            } else {
                failedDecoding = true
                self.configuration.map(self.configure)
            }
        }
    }

    private func showAnimatedPhoto(_ url: URL, media: TimelineMediaPreviewItem.Media) {
        quality = .full
        photoView.showAnimatedImage(url: url, aspectRatio: media.aspectRatio) { [weak self] in
            self?.failedDecoding = true
            self?.configuration.map { self?.configure($0) }
        }
    }

    /// The video's poster sits where the player draws its picture, so the first frame replaces it in place.
    private func showPoster(_ media: TimelineMediaPreviewItem.Media, configuration: Configuration) {
        photoView.isHidden = false
        photoView.isZoomEnabled = false
        showThumbnail(media, configuration: configuration)
    }

    /// The chat bubble's picture, straight from memory when the bubble drew it, at the media's final frame.
    private func showThumbnail(_ media: TimelineMediaPreviewItem.Media, configuration: Configuration) {
        guard quality < .thumbnail, thumbnailTask == nil, let request = media.bubbleImage, let mediaProvider = configuration.mediaProvider else {
            if quality == .none {
                photoView.show(nil, aspectRatio: media.aspectRatio)
            }
            return
        }
        if let image = mediaProvider.imageFromSource(request.source, size: request.size) {
            show(image, quality: .thumbnail, media: media)
            return
        }
        photoView.show(nil, aspectRatio: media.aspectRatio)
        let load = mediaProvider.loadImageRetryingOnReconnection(request.source, size: request.size)
        thumbnailTask = Task { [weak self] in
            let image = try? await withTaskCancellationHandler {
                try await load.value
            } onCancel: {
                load.cancel()
            }
            guard let self, let image, !Task.isCancelled, page == configuration.page else { return }
            show(image, quality: .thumbnail, media: media)
        }
    }

    private func show(_ image: UIImage, quality: Quality, media: TimelineMediaPreviewItem.Media) {
        guard quality > self.quality else { return }
        self.quality = quality
        photoView.show(image, aspectRatio: media.aspectRatio, fullPixelWidth: quality == .full ? image.size.width * image.scale : nil)
    }

    /// Every pixel of the photo, once the user zooms in.
    private func loadFullPhoto() {
        guard quality < .full, let configuration, let media = configuration.media, media.kind == .image,
              let url = media.fileURL else {
            return
        }
        Task { [weak self] in
            guard let image = await configuration.imageLoader.image(for: url, resolution: .full),
                  let self, page == configuration.page else { return }
            show(image, quality: .full, media: media)
        }
    }

    // MARK: Status

    private func setStatus(_ status: MediaViewerPageStatus) {
        guard status != self.status else { return }
        self.status = status
        statusView.isHidden = status == .none
        statusView.configuration = UIHostingConfiguration { [weak self] in
            MediaViewerPageStatusView(status: status,
                                      openFile: { self?.configuration?.openFile() },
                                      play: { self?.configuration?.play() })
        }
        .margins(.all, 0)
    }

    private func updateAccessibility(_ configuration: Configuration) {
        guard let media = configuration.media, media.kind == .image else {
            photoView.isAccessibilityElement = false
            return
        }
        photoView.isAccessibilityElement = true
        photoView.accessibilityLabel = media.caption ?? media.filename ?? L10n.commonImage
        photoView.accessibilityTraits = .image
    }
}

/// A view that only takes the touches its subviews take.
final class MediaViewerPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

// MARK: - Status

/// What a page shows in its middle, if anything.
enum MediaViewerPageStatus: Equatable {
    case none
    case progress(text: String?)
    case scanFailure(ContentScanningFailure)
    case downloadError
    case file(name: String, details: String?, canOpen: Bool)
    /// The big ▶ over a video or audio that isn't playing, with a spinner while its file downloads.
    case play(isLoading: Bool)

    var isInteractive: Bool {
        switch self {
        case .file, .play: true
        default: false
        }
    }
}

struct MediaViewerPageStatusView: View {
    let status: MediaViewerPageStatus
    var openFile: () -> Void = { }
    var play: () -> Void = { }

    var body: some View {
        switch status {
        case .none:
            EmptyView()
        case .progress(let text):
            MediaViewerProgress(text: text)
        case .scanFailure(let failure):
            TimelineMediaContentScanningFailureView(failure: failure)
        case .downloadError:
            MediaViewerDownloadError()
        case .file(let name, let details, let canOpen):
            MediaViewerFileCard(name: name, details: details, canOpen: canOpen, openFile: openFile)
        case .play(let isLoading):
            MediaViewerPlayButton(isLoading: isLoading, action: play)
        }
    }
}

/// The big glass ▶ that says a video is there to be played.
private struct MediaViewerPlayButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.compound.iconPrimary)
                } else {
                    CompoundIcon(\.playSolid, size: .custom(32), relativeTo: .compound.headingXLBold)
                        .foregroundStyle(.compound.iconPrimary)
                        .offset(x: 2) // The triangle's weight sits left of its box.
                }
            }
            .frame(width: 76, height: 76)
            .spiralGlass(in: Circle(), isInteractive: true)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.a11yPlay)
    }
}

/// A file that isn't a photo or a video: its name and size, and QuickLook to open it.
private struct MediaViewerFileCard: View {
    let name: String
    let details: String?
    let canOpen: Bool
    let openFile: () -> Void

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            CompoundIcon(\.document, size: .custom(56), relativeTo: .compound.headingXLBold)
                .foregroundStyle(.compound.iconSecondary)
                .accessibilityHidden(true)

            VStack(spacing: CompoundDesignTokens.space1X) {
                Text(name)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)

                if let details {
                    Text(details)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }
            }

            Button(action: openFile) {
                Text(UntranslatedL10n.screenMediaViewerOpen)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .padding(.horizontal, CompoundDesignTokens.space8X)
                    .frame(minHeight: 44)
                    .spiralGlass(in: Capsule(), isInteractive: true)
            }
            .buttonStyle(.plain)
            .disabled(!canOpen)
            .opacity(canOpen ? 1 : 0.4)
        }
        .padding(.horizontal, CompoundDesignTokens.space8X)
    }
}

private struct MediaViewerProgress: View {
    var text: String?

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space8X) {
            ProgressView()
                .controlSize(.large)
                .tint(.compound.iconPrimary)

            if let text {
                Text(text)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
            }
        }
    }
}

private struct MediaViewerDownloadError: View {
    var body: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            CompoundIcon(\.errorSolid, size: .custom(48), relativeTo: .compound.headingLG)
                .foregroundStyle(.compound.iconCriticalPrimary)
                .accessibilityHidden(true)

            VStack(spacing: CompoundDesignTokens.space1X) {
                Text(L10n.commonDownloadFailed)
                    .font(.compound.headingMDBold)
                    .foregroundStyle(.compound.textPrimary)
                    .multilineTextAlignment(.center)
                Text(L10n.screenMediaBrowserDownloadErrorMessage)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space6X)
        .padding(.vertical, CompoundDesignTokens.space10X)
        .background(.compound.bgSubtlePrimary, in: RoundedRectangle(cornerRadius: SpiralRadius.listCard))
        .padding(.horizontal, CompoundDesignTokens.space8X)
    }
}

private extension TimelineMediaPreviewItem.Media {
    /// The file's type and size, for the file card.
    var fileDetails: String? {
        let size = fileSize.map { UInt($0).formatted(.byteCount(style: .file)) }
        let parts = [contentType, size].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
