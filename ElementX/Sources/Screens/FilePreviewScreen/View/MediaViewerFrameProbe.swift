//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): late frames while the viewer moves, in DEBUG and Staging builds only.
// One line per gesture; grep `[MediaViewer][frames]`.
//

import SwiftUI

@MainActor
enum MediaViewerFrameProbe {
    /// What the viewer was doing while the frames were counted.
    enum Gesture: String {
        case open, close, page, zoom
        case swipeDown = "swipe-down"
    }

    #if DEBUG || SPIRAL_STAGING
    private struct Running {
        let gesture: Gesture
        let probe: SpiralAppFrameProbe
        let began: ContinuousClock.Instant
    }

    private static var running: Running?
    #endif

    /// Starts counting, ending any gesture still counted.
    static func begin(_ gesture: Gesture) {
        #if DEBUG || SPIRAL_STAGING
        if let running {
            end(running.gesture)
        }
        running = Running(gesture: gesture, probe: SpiralAppFrameProbe(), began: .now)
        #endif
    }

    /// Counts each page swipe from the finger touching down until the page has settled, the same way whatever pages.
    static func track(pageSwipes recognizer: UIPanGestureRecognizer) {
        #if DEBUG || SPIRAL_STAGING
        recognizer.addTarget(PageSwipeObserver.shared, action: #selector(PageSwipeObserver.handle(_:)))
        #endif
    }

    /// Logs the gesture's frames, if it is the one being counted.
    static func end(_ gesture: Gesture) {
        #if DEBUG || SPIRAL_STAGING
        guard let running, running.gesture == gesture else { return }
        self.running = nil
        let duration = running.began.duration(to: .now).components
        let milliseconds = duration.seconds * 1000 + duration.attoseconds / 1_000_000_000_000_000
        MXLog.info("[MediaViewer][frames] \(gesture.rawValue) \(milliseconds)ms — \(running.probe.finish())")
        #endif
    }
}

#if DEBUG || SPIRAL_STAGING
private final class PageSwipeObserver: NSObject {
    static let shared = PageSwipeObserver()
    /// Long enough for a paging scroll view to decelerate onto its page.
    private static let settleTime: Duration = .milliseconds(600)
    private var settling: Task<Void, Never>?

    @objc func handle(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            settling?.cancel()
            MediaViewerFrameProbe.begin(.page)
        case .ended, .cancelled, .failed:
            settling = Task {
                try? await Task.sleep(for: Self.settleTime)
                guard !Task.isCancelled else { return }
                MediaViewerFrameProbe.end(.page)
            }
        default:
            break
        }
    }
}
#endif
