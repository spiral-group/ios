//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): a photo in Spiral's own viewer — fitted to the screen, pinch and
// double-tap to zoom, animated GIFs playing. The frame comes from the media's shape, so the chat's thumbnail and
// then the photo itself draw in the same place and nothing moves when the photo arrives.
//

import AVFoundation
import Kingfisher
import SwiftUI

/// A scroll view that zooms its image. The viewer checks ``isZoomedIn`` before a swipe down may close it.
final class MediaViewerZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    /// Called as a pinch or double tap starts zooming in, to swap in every pixel of the photo.
    var onZoomStarted: () -> Void = { }

    /// Whether a pinch or a double tap zooms: not on a video's poster.
    var isZoomEnabled = true {
        didSet {
            guard isZoomEnabled != oldValue else { return }
            pinchGestureRecognizer?.isEnabled = isZoomEnabled
            doubleTap.isEnabled = isZoomEnabled
            zoomOut()
        }
    }

    private let imageView = AnimatedImageView()
    private let doubleTap = UITapGestureRecognizer()
    /// The media's width over its height, which sets the frame before any pixels are there.
    private var aspectRatio: CGFloat?
    /// The bounds and shape the image was last fitted to; zooming leaves them alone.
    private var fitted: (bounds: CGSize, aspectRatio: CGFloat)?
    /// The pixel width of the whole photo, for how far it may zoom.
    private var fullPixelWidth: CGFloat?
    private var animatedURL: URL?

    private static let doubleTapScale: CGFloat = 2.5

    var isZoomedIn: Bool {
        zoomScale > minimumZoomScale + 0.01
    }

    init() {
        super.init(frame: .zero)
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true

        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        addSubview(imageView)

        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `image` at the frame `aspectRatio` gives, or the image's own shape without one. A sharper image of the
    /// same shape replaces a blurrier one in place, keeping the zoom.
    func show(_ image: UIImage?, aspectRatio: CGFloat?, fullPixelWidth: CGFloat? = nil) {
        if animatedURL != nil {
            imageView.kf.cancelDownloadTask()
            animatedURL = nil
        }
        self.aspectRatio = aspectRatio ?? image.flatMap { $0.size.height > 0 ? $0.size.width / $0.size.height : nil }
        if let fullPixelWidth {
            self.fullPixelWidth = fullPixelWidth
            updateMaximumZoomScale()
        }
        imageView.image = image
        setNeedsLayout()
    }

    /// Plays an animated GIF from its file.
    func showAnimatedImage(url: URL, aspectRatio: CGFloat?, onFailure: @escaping () -> Void) {
        guard animatedURL != url else { return }
        animatedURL = url
        imageView.kf.setImage(with: .provider(LocalFileImageDataProvider(fileURL: url)),
                              options: [.backgroundDecode, .keepCurrentImageWhileLoading]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                self.aspectRatio = aspectRatio ?? value.image.size.width / max(1, value.image.size.height)
                setNeedsLayout()
            case .failure(let error):
                MXLog.error("Failed decoding the image: \(error)")
                onFailure()
            }
        }
    }

    /// Empties the view for another page.
    func reset() {
        imageView.kf.cancelDownloadTask()
        animatedURL = nil
        imageView.image = nil
        aspectRatio = nil
        fullPixelWidth = nil
        fitted = nil
        setZoomScale(minimumZoomScale, animated: false)
    }

    func zoomOut() {
        if isZoomedIn {
            setZoomScale(minimumZoomScale, animated: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let aspectRatio, aspectRatio > 0, bounds.width > 0, bounds.height > 0 else { return }

        // Only a new shape or new bounds refit; a sharper image of the same shape keeps the frame and the zoom.
        if fitted?.bounds != bounds.size || abs((fitted?.aspectRatio ?? 0) - aspectRatio) > 0.01 {
            fitted = (bounds.size, aspectRatio)
            setZoomScale(minimumZoomScale, animated: false)
            let fittedSize = AVMakeRect(aspectRatio: CGSize(width: aspectRatio, height: 1),
                                        insideRect: CGRect(origin: .zero, size: bounds.size)).size
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            contentSize = fittedSize
            updateMaximumZoomScale()
        }

        centerImage()
    }

    // MARK: UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        MediaViewerFrameProbe.begin(.zoom)
        onZoomStarted()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        MediaViewerFrameProbe.end(.zoom)
    }

    // MARK: Private

    /// Zoom far enough to see every pixel of a large photo, and at least as far as a double tap goes.
    private func updateMaximumZoomScale() {
        let fittedWidth = (fitted.map { _ in imageView.frame.width / zoomScale }) ?? 0
        let pixelScale = fittedWidth > 0 ? (fullPixelWidth ?? 0) / (fittedWidth * traitCollection.displayScale) : 0
        maximumZoomScale = max(Self.doubleTapScale * 1.6, pixelScale)
    }

    /// Keeps a photo smaller than the screen in its middle.
    private func centerImage() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard imageView.image != nil else { return }

        if isZoomedIn {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            onZoomStarted()
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / Self.doubleTapScale, height: bounds.height / Self.doubleTapScale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
