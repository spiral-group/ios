//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066): the experiment that should have come first.
//
// The whole design rests on one unexamined assumption: that a `WKWebView`
// which has painted keeps painting after it is moved to a different parent.
// Every row in a timeline is recycled, so the web view is moved constantly —
// and if WebKit does not repaint after a move, no amount of bookkeeping in the
// registry can fix a grey row, because the pixels are gone and nothing asks
// for them back.
//
// This measures it with no Spiral code in the way: a plain web view, a solid
// colour, a snapshot before and after a reparent.
//

@testable import Spiral
import Testing
import UIKit
import WebKit

@MainActor
struct SpiralAppReparentExperimentTests {
    /// Does a painted web view still paint after moving to a new parent?
    @Test
    func aWebViewKeepsPaintingAfterItIsMovedToANewParent() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let delegate = LoadWatcher()
        webView.navigationDelegate = delegate

        let firstWindow = Self.makeVisibleWindow()
        let firstParent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        firstWindow.rootViewController?.view.addSubview(firstParent)
        firstParent.addSubview(webView)

        webView.loadHTMLString("<body style='margin:0;background:#ff0000'></body>", baseURL: nil)
        try await delegate.waitForLoad()
        try await Task.sleep(for: .milliseconds(300))

        let before = try await snapshot(of: webView)
        #expect(before == .red, "the web view never painted in the first place: \(before)")

        // The move a recycled row makes: out of one parent, into another.
        let secondParent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        firstWindow.rootViewController?.view.addSubview(secondParent)
        webView.removeFromSuperview()
        secondParent.addSubview(webView)
        try await Task.sleep(for: .milliseconds(300))

        let afterSameWindow = try await snapshot(of: webView)
        #expect(afterSameWindow == .red, "a reparent within one window lost the pixels: \(afterSameWindow)")

        // The harder move: a different window entirely, which is what happens
        // when a row is recycled across a timeline rebuild.
        let secondWindow = Self.makeVisibleWindow()
        let thirdParent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        secondWindow.rootViewController?.view.addSubview(thirdParent)
        webView.removeFromSuperview()
        thirdParent.addSubview(webView)
        try await Task.sleep(for: .milliseconds(300))

        let afterNewWindow = try await snapshot(of: webView)
        #expect(afterNewWindow == .red, "a move to another window lost the pixels: \(afterNewWindow)")
    }

    /// And the case the timeline actually creates: OUT of every window for a
    /// moment — which is what `removeFromSuperview` in the pool does — and
    /// then back in.
    @Test
    func aWebViewKeepsPaintingAfterBeingDetachedAndReattached() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let delegate = LoadWatcher()
        webView.navigationDelegate = delegate

        let window = Self.makeVisibleWindow()
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.rootViewController?.view.addSubview(parent)
        parent.addSubview(webView)

        webView.loadHTMLString("<body style='margin:0;background:#ff0000'></body>", baseURL: nil)
        try await delegate.waitForLoad()
        try await Task.sleep(for: .milliseconds(300))
        #expect(try await snapshot(of: webView) == .red)

        // Detached: no window at all, as a parked host is.
        webView.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(500))

        // And back.
        parent.addSubview(webView)
        try await Task.sleep(for: .milliseconds(300))

        let after = try await snapshot(of: webView)
        #expect(after == .red, "a web view that spent time out of any window came back blank: \(after)")
    }

    // MARK: - Helpers

    /// A window WebKit will actually paint into: on a scene, key and visible,
    /// with a root view controller. A bare `UIWindow` with `isHidden = false`
    /// is not enough — the first snapshot came back solid black, which is what
    /// "nothing rendered" looks like and nearly cost an afternoon chasing a
    /// reparenting bug that the harness had invented.
    private static func makeVisibleWindow() -> UIWindow {
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        return window
    }

    private enum Pixel: Equatable, CustomStringConvertible {
        case red
        case blank
        case other(String)

        var description: String {
            switch self {
            case .red: "red"
            case .blank: "blank/white"
            case .other(let value): value
            }
        }
    }

    /// The stand-in is taken in `willMove(toWindow:)` and the view is gone a
    /// moment later, so the picture has to survive that. A web view with no
    /// window is reported to leave a snapshot unanswered.
    @Test
    func aSnapshotTakenJustBeforeLeavingAWindowStillArrives() async throws {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let delegate = LoadWatcher()
        webView.navigationDelegate = delegate
        let window = Self.makeVisibleWindow()
        window.rootViewController?.view.addSubview(webView)
        webView.loadHTMLString("<body style='margin:0;background:#ff0000'></body>", baseURL: nil)
        try await delegate.waitForLoad()
        try await Task.sleep(for: .milliseconds(300))

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        configuration.afterScreenUpdates = false
        let start = ContinuousClock.now
        var result: UIImage?
        var hasAnswered = false
        webView.takeSnapshot(with: configuration) { image, _ in
            result = image
            hasAnswered = true
        }
        let cost = start.duration(to: .now)
        webView.removeFromSuperview()

        let deadline = ContinuousClock.now + .seconds(2)
        while !hasAnswered, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        MXLog.info("[experiment] takeSnapshot held the main thread \(cost), answered: \(hasAnswered)")
        let image = try #require(result, "no picture came back once the view had left its window")
        #expect(try pixel(of: image) == .red)
    }

    /// The app's only way to pause a post without a shell release. WebKit
    /// counts a web view in a window as visible however far it has scrolled,
    /// so this is what taking it out of the window has to buy.
    @Test
    func aPageOutOfAnyWindowStopsItsAnimationFrames() async throws {
        let (webView, window) = try await Self.countingAnimationFrames()
        let parent = try #require(window.rootViewController?.view)
        let running = try await Self.framesCounted(by: webView)
        try await Task.sleep(for: .milliseconds(500))
        let frameRate = try await Self.framesCounted(by: webView) - running
        #expect(frameRate > 5, "the page never animated, so this proves nothing: \(frameRate)")

        webView.removeFromSuperview()
        try await Task.sleep(for: .milliseconds(100))
        parent.addSubview(webView)
        let before = try await Self.framesCounted(by: webView)
        webView.removeFromSuperview()
        try await Task.sleep(for: .seconds(1))
        parent.addSubview(webView)
        let gained = try await Self.framesCounted(by: webView) - before

        MXLog.info("[experiment] in a window \(frameRate) frames in 0.5 s; out of one \(gained) in 1 s")
        #expect(gained < frameRate, "a page out of any window went on animating: \(gained) frames in 1 s")
    }

    /// The audit's open question, recorded rather than asserted: it is
    /// WebKit's to change, and the registry doesn't rely on it.
    @Test
    func whatHidingAWebViewDoesToItsAnimationFrames() async throws {
        let (webView, _) = try await Self.countingAnimationFrames()
        let before = try await Self.framesCounted(by: webView)

        webView.isHidden = true
        try await Task.sleep(for: .seconds(1))
        let hiddenState = try await webView.evaluateJavaScript("document.visibilityState") as? String
        let gained = try await Self.framesCounted(by: webView) - before

        MXLog.info("[experiment] hidden: document is \(hiddenState ?? "?"), \(gained) frames in 1 s")
    }

    private static func countingAnimationFrames() async throws -> (WKWebView, UIWindow) {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let delegate = LoadWatcher()
        webView.navigationDelegate = delegate
        let window = makeVisibleWindow()
        window.rootViewController?.view.addSubview(webView)
        webView.loadHTMLString("<script>window.frames_=0;(function t(){frames_++;requestAnimationFrame(t)})()</script>", baseURL: nil)
        try await delegate.waitForLoad()
        try await Task.sleep(for: .milliseconds(300))
        return (webView, window)
    }

    private static func framesCounted(by webView: WKWebView) async throws -> Int {
        try await webView.evaluateJavaScript("frames_") as? Int ?? 0
    }

    /// What the web view is actually showing, read from its own snapshot.
    private func snapshot(of webView: WKWebView) async throws -> Pixel {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        configuration.afterScreenUpdates = true

        let image: UIImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? SnapshotError.noImage)
                }
            }
        }

        return try pixel(of: image)
    }

    private func pixel(of image: UIImage) throws -> Pixel {
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw SnapshotError.noPixels
        }

        // Bytes are BGRA or RGBA depending on the context; check both orders
        // for "mostly red" rather than trusting one.
        let a = Int(bytes[0]), b = Int(bytes[1]), c = Int(bytes[2])
        if (a > 200 && b < 80 && c < 80) || (c > 200 && b < 80 && a < 80) {
            return .red
        }
        if a > 200, b > 200, c > 200 {
            return .blank
        }
        return .other("rgb-ish(\(a),\(b),\(c))")
    }

    private enum SnapshotError: Error {
        case noImage
        case noPixels
    }

    private final class LoadWatcher: NSObject, WKNavigationDelegate {
        private var continuations: [CheckedContinuation<Void, Error>] = []
        private var finished = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished = true
            let waiting = continuations
            continuations.removeAll()
            for continuation in waiting {
                continuation.resume()
            }
        }

        func waitForLoad() async throws {
            if finished { return }
            try await withCheckedThrowingContinuation { continuation in
                continuations.append(continuation)
            }
        }
    }
}
