//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.28): warm web views, reused.
//
// Creating a `WKWebView` is the cost. Not loading the document — creating the
// view: a WebContent process, the shell document, the module graph evaluating,
// `__spiralShell` installing. Every source on the subject says the same and so
// did our log: twelve posts scrolled back and forth paid that price ninety
// times in five minutes, once per eviction, when the host already had an
// `unmount()` that keeps the shell warm and the gate had proved a reused web
// view is safe ("no marker from a previous app in this realm").
//
// So an evicted app gives its host back here, and the next app takes it —
// skipping everything but the artifact.
//
// The one thing this must not weaken: an app may only ever see the state of
// the post it is mounted on. That used to be enforced by binding the bridge at
// construction. It is now enforced by `unmount()` unbinding BEFORE the frame
// goes and `bind()` happening before the next artifact runs, so a parked host
// answers every call with `gone`. The test for that is not "it works", it is
// "a parked host cannot reach the old session".
//

import Foundation

@MainActor
final class SpiralAppHostPool {
    /// How many warm hosts to keep when nothing is using them.
    ///
    /// Two, because the common case is one row leaving as one arrives, and a
    /// second covers the overshoot (§5.15) without holding a third process
    /// that nothing is about to need. Parked hosts are the cheap kind of live
    /// web view — no artifact, nothing painting — but they are still a process
    /// each, and the cap on LIVE apps was never meant to be doubled quietly.
    static let maxParked = 2

    private var parked: [SpiralAppHostProtocol] = []
    private let makeHost: @MainActor () -> SpiralAppHostProtocol

    /// For tests and the developer screen.
    var parkedCount: Int {
        parked.count
    }

    /// How long an app gets to leave (M3). `while (true) {}` in a frame
    /// blocks the shell's own JavaScript with it, so an unmount that waits
    /// for an answer waits for ever — and with it the eviction that asked,
    /// and every post behind that.
    private let unmountDeadline: Duration

    init(unmountDeadline: Duration = .seconds(2), makeHost: @escaping @MainActor () -> SpiralAppHostProtocol) {
        self.unmountDeadline = unmountDeadline
        self.makeHost = makeHost
    }

    /// A host with the shell already warm, or a new one if none is parked.
    ///
    /// Either way it is UNBOUND: the caller binds it to a session before
    /// mounting, and a host handed out here answers `gone` until then.
    func acquire() -> SpiralAppHostProtocol {
        if let host = parked.popLast() {
            host.onContentProcessDied = nil
            return host
        }
        return makeHost()
    }

    /// Have a host warming for the next `acquire`, unless one already is.
    ///
    /// Its process launches and its shell loads while nothing waits for them.
    /// It serves no post and holds no artifact, so it reaches nothing.
    func prewarm() {
        guard parked.isEmpty else { return }
        park(makeHost())
    }

    /// Give a host back. Its app is destroyed and the bridge unbound; the
    /// shell stays warm for the next `acquire`. Beyond `maxParked`, the host
    /// is destroyed instead of kept, and so is one whose app does not answer
    /// the unmount in time — a wedged shell is not warm.
    @discardableResult
    func release(_ host: SpiralAppHostProtocol) async -> SpiralAppUnmount {
        guard await unmount(host) else {
            MXLog.error("[SpiralApp] an app did not leave in \(unmountDeadline) — destroying its host")
            host.onContentProcessDied = nil
            host.containerView.removeFromSuperview()
            host.destroy()
            return .wedged
        }
        host.onContentProcessDied = nil
        // Out of whatever row was showing it, NOW. SwiftUI will get round to
        // removing it when the old row's slot updates, but the next app may
        // take this host before that — and a mount that paints into a view
        // still attached to a row that is scrolling away paints into nothing
        // the new row will show. Measured: a warm host mounts in ~40 ms, which
        // is faster than a SwiftUI update cycle.
        host.containerView.removeFromSuperview()

        // A host may only be parked once. Two entries for one host would be
        // handed to two apps, and one web view cannot serve two — they take it
        // from each other, and the loser is a grey row. The instance refuses
        // to stop twice as well; this is the second lock on the same door,
        // because the cost of being wrong here is invisible until someone is
        // staring at it.
        guard !parked.contains(where: { $0 === host }) else { return .answered }

        if parked.count < Self.maxParked {
            park(host)
        } else {
            host.destroy()
        }
        return .answered
    }

    /// A parked host that dies has no warm shell left to give, and the next
    /// app must not be handed a web view that will never paint.
    private func park(_ host: SpiralAppHostProtocol) {
        host.onContentProcessDied = { [weak self, weak host] in
            guard let self, let host else { return }
            parked.removeAll { $0 === host }
            host.destroy()
        }
        parked.append(host)
    }

    /// Whether `host` unmounted inside the deadline. The call itself is not
    /// cancelled — WebKit's is not cancellable — only no longer waited for.
    private func unmount(_ host: SpiralAppHostProtocol) async -> Bool {
        final class Latch {
            var isClosed = false
        }
        let latch = Latch()
        let deadline = unmountDeadline
        // `host` weakly (N1): a wedged host is destroyed at the deadline,
        // and this task must not be what keeps it — and its web view — alive.
        return await withCheckedContinuation { continuation in
            Task { @MainActor [weak host] in
                await host?.unmount()
                guard !latch.isClosed else { return }
                latch.isClosed = true
                continuation.resume(returning: true)
            }
            Task { @MainActor in
                try? await Task.sleep(for: deadline)
                guard !latch.isClosed else { return }
                latch.isClosed = true
                continuation.resume(returning: false)
            }
        }
    }

    /// Destroy every parked host. For when the timeline goes away: a warm
    /// shell for a room nobody is in is a process for nothing.
    func drain() {
        for host in parked {
            host.destroy()
        }
        parked.removeAll()
    }
}

/// How an app left its host.
enum SpiralAppUnmount {
    case answered
    /// It did not answer in time; its host was destroyed. Counted as a death.
    case wedged
}
