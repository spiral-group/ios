//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (security pass 2, posts H2): whether the reader asked.
//
// A post is somebody else's code running as the reader. A ping pushes people
// as the reader and `ui.expand` takes the reader's screen — and both used to
// need nothing but the post's own say-so: the frame reports
// `userActivation`, and a frame can say what it likes. So the host looks for
// itself. A touch on the post's own view is recorded natively, and those two
// need one in the last few seconds. Without one a write still goes, and its
// ping reaches only whoever it answers (decision 235): games answer for the
// reader, keyboards never touch the container, and «your move» still has to
// reach the mover. The write bucket bounds them all.
//

import UIKit.UIGestureRecognizerSubclass

/// `capacity` at once, then one more every `refillInterval`.
struct SpiralAppTokenBucket {
    let capacity: Double
    let refillInterval: TimeInterval
    private var tokens: Double
    private var updatedAt: TimeInterval?

    init(capacity: Int, refillInterval: TimeInterval) {
        self.capacity = Double(capacity)
        self.refillInterval = refillInterval
        tokens = Double(capacity)
    }

    /// Take one token if there is one.
    mutating func take(at now: TimeInterval) -> Bool {
        if let updatedAt {
            tokens = min(capacity, tokens + max(0, now - updatedAt) / refillInterval)
        }
        updatedAt = now
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }

    /// Shared writes: ten at once, then one per 300 ms — the SDK's own
    /// coalescing window (`COALESCE_MS`), so an app on our SDK never meets
    /// the limit however long a drag goes on. What it stops is an app that
    /// skips the SDK: about 26 actions for one tap instead of hundreds.
    static var sharedWrites: Self {
        .init(capacity: 10, refillInterval: 0.3)
    }

    /// `ui.haptic`: ten a second. Feel, not data, so not behind the touch —
    /// an opponent's move may buzz — but never a buzz that does not stop.
    static var haptics: Self {
        .init(capacity: 10, refillInterval: 0.1)
    }
}

/// When the reader last touched this post, as the host saw it.
@MainActor
final class SpiralAppActivation {
    /// How long a touch counts for. Long enough for a tap and the pings it
    /// sets off — the SDK's coalescing, a send, an animation — and short
    /// enough that a post cannot act on a touch the reader has forgotten.
    static let window: TimeInterval = 5

    private let now: () -> TimeInterval
    private var lastTouch: TimeInterval?
    /// Touches at or before this no longer open the screen: the last expand,
    /// or the viewer closing. One expand per touch, none on the way out.
    private var expandFloor = -TimeInterval.infinity
    private var haptics = SpiralAppTokenBucket.haptics

    /// - Parameter now: seconds on a monotonic clock — the one `UITouch`
    ///   stamps touches with. Injected so a test can move it.
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func recordTouch() {
        lastTouch = now()
    }

    /// A touch that turned out to be the timeline scrolling, not the post.
    func revokeTouch() {
        lastTouch = nil
    }

    /// Whether the reader touched the post in the last `window` seconds.
    var hasRecentTouch: Bool {
        guard let lastTouch else { return false }
        return now() - lastTouch <= Self.window
    }

    /// Take the screen once for a recent touch; the next expand needs a new one.
    func consumeForExpand() -> Bool {
        guard hasRecentTouch, let lastTouch, lastTouch > expandFloor else { return false }
        expandFloor = now()
        return true
    }

    /// The viewer closed: nothing touched before now may open it again.
    func viewerDismissed() {
        expandFloor = now()
    }

    func allowsHaptic() -> Bool {
        haptics.take(at: now())
    }
}

/// Records touches on a post's view without taking part in them.
///
/// Never recognises, never cancels, never delays, and is never prevented:
/// the web view's own recognisers and the timeline's see exactly what they
/// saw before it existed.
final class SpiralAppTouchRecorder: UIGestureRecognizer {
    private let activation: SpiralAppActivation

    init(activation: SpiralAppActivation) {
        self.activation = activation
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        activation.recordTouch()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        noteUnlessScrolling()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        noteUnlessScrolling()
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    /// A finger that lands on a post and scrolls the timeline touched the
    /// timeline, not the post: the touch it began with is taken back.
    private func noteUnlessScrolling() {
        var ancestor = view?.superview
        var scrolling = false
        while let current = ancestor, !scrolling {
            scrolling = (current as? UIScrollView)?.isDragging == true
            ancestor = current.superview
        }
        if scrolling {
            activation.revokeTouch()
        } else {
            activation.recordTouch()
        }
    }
}
