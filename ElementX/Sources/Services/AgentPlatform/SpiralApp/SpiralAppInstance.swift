//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007): one running app — a session bound to
// a host.
//
// This exists because the binding was a checklist and someone skipped a line.
// Starting an app is five steps: make a session, bind the bridge to it, forward
// its state into the running app, start it, mount the artifact. The harness did
// all five. The timeline did four — it never forwarded — so an action taken on
// another phone changed nothing on screen until the row was rebuilt and the app
// happened to read again. Measured between two simulators: the feed delivered,
// the session folded to `{"count":6}`, and the app went on showing 5.
//
// A checklist repeated at two call sites will be missed at one of them. The
// binding is therefore a type, and the forwarding is not something a caller can
// forget to ask for.
//
// What stays with the caller is what genuinely differs: which session, whether
// to pool, and what else to do when the state changes. `snapshots` is published
// for that, but nothing depends on anyone subscribing to it.
//

import Combine
import Foundation
import UIKit

@MainActor
final class SpiralAppInstance {
    /// The view to place on screen. Exists from construction, so a row has
    /// something real to hold before the app has started.
    var containerView: UIView {
        host.containerView
    }

    /// Where the app is being shown: a row, or the full-screen viewer.
    ///
    /// The app is told, because the two differ in one thing it cannot see
    /// from inside a frame: a row never scrolls its own overflow (a swipe
    /// there belongs to the timeline), the viewer may. The bootstrap marks
    /// the document; the kit's `.s-scroll` and the SDK's `useViewport` read
    /// the mark.
    func setViewport(_ mode: SpiralAppViewportMode) {
        guard mode != viewportMode else { return }
        viewportMode = mode
        let host = host
        Task { await host.push(["kind": "viewport.changed", "mode": mode.rawValue]) }
    }

    private var viewportMode: SpiralAppViewportMode = .row

    /// Called when the running app asks for the whole screen (`ui.expand`).
    ///
    /// Owned by the row, because only it knows where "full screen" is. An
    /// instance with nobody listening simply does not grow, which is what a
    /// preview should do.
    var onExpandRequested: (() -> Void)? {
        get { session.onExpandRequested }
        set { session.onExpandRequested = newValue }
    }

    /// State as the room agrees it is. For a caller that wants to react — the
    /// timeline's quiet card, the harness's readout — never for forwarding,
    /// which is done here.
    var snapshots: AnyPublisher<SpiralAppStateReader.Snapshot, Never> {
        session.snapshotPublisher
    }

    /// Called when the system kills this app's web content process. The app is
    /// gone at that point whatever the row still shows.
    var onContentProcessDied: (@MainActor () -> Void)? {
        get { host.onContentProcessDied }
        set { host.onContentProcessDied = newValue }
    }

    private var session: SpiralAppSessionProtocol
    private let pool: SpiralAppHostPool
    private var host: SpiralAppHostProtocol
    private var forwarding: AnyCancellable?
    private var membersForwarding: AnyCancellable?
    /// Whether this app has already been taken down.
    ///
    /// Stopping twice used to give the host back to the pool twice, and the
    /// pool would then hand ONE web view to TWO apps. Both showed it; each
    /// stole it from the other; whichever lost was a grey rectangle the reader
    /// was looking at. It is reachable in ordinary use: an eviction stops an
    /// app WHILE it is starting, and the start's own cleanup then stops it
    /// again. Measured 2026-09-15 — two posts trading one container back and
    /// forth twice a second.
    private var isStopped = false

    /// Bind a session to a host taken from the pool.
    ///
    /// The bridge is bound HERE, before anything can be mounted, because it
    /// must answer from this session and no other: an app may only ever see
    /// the state of the post it is mounted on. The host may have served
    /// another app a moment ago — that is the point of the pool — and it
    /// arrives unbound, answering `gone`, until this line.
    init(session: SpiralAppSessionProtocol, pool: SpiralAppHostPool) {
        self.session = session
        self.pool = pool
        host = pool.acquire()
        host.bind { [weak session] method, args, _ in
            guard let session else {
                return SpiralAppBridge.failure(code: "gone", message: "this app is no longer mounted")
            }
            return await session.answer(method: method, args: args)
        }

        // Subscribed before anything is mounted, deliberately. A push to an
        // unmounted host is dropped harmlessly, whereas subscribing after the
        // mount would leave a window between the app's own first read and this
        // subscription in which someone else's action could be lost for good.
        forwarding = session.snapshotPublisher
            .sink { [weak host] snapshot in
                Task {
                    await host?.push(["kind": "state.changed",
                                      "state": snapshot.state.jsonObject,
                                      "seq": snapshot.seq])
                }
            }
        // The people too (§ 5.67): someone who joins while the post is
        // mounted is a player at once, not on the next mount.
        membersForwarding = session.membersPublisher
            .sink { [weak host] payload in
                Task {
                    // `data` is exactly what `members.basic.read` answers,
                    // so the SDK reads both with one parser.
                    await host?.push(["kind": "members.changed", "data": payload])
                }
            }
    }

    /// How starting an app ended.
    ///
    /// Two failures that used to be one `false`, and the difference decides
    /// whether the reader ever sees the app. An INTERRUPTED start is not the
    /// artifact's fault — its slot was taken, or the page churned under the
    /// call — so the post deserves another turn. A REFUSED one is the app
    /// asking for something it will not get, and trying again would only
    /// refuse it again.
    ///
    /// Measured 2026-09-16: two posts ended their day on an interrupted start
    /// and never tried again, so they sat on screen as cards while everything
    /// around them ran.
    enum Outcome {
        case started
        case interrupted
        case refused
    }

    /// Start listening, then run the artifact.
    func start(_ artifact: SpiralAppArtifact, instanceID: String) async -> Outcome {
        guard let capabilities = SpiralAppCapability.granted(requestedBy: artifact.manifest,
                                                             from: SpiralAppCapability.production) else {
            // Refused whole rather than granted in part: an app expecting
            // something it will not get is better not started than started
            // half-working, inside a frame whose console reaches nobody.
            MXLog.error("[SpiralApp] \(instanceID) asked for a capability this runtime does not grant")
            return .refused
        }

        await session.start()
        await host.waitUntilReady()

        do {
            try await host.mount(SpiralAppMount(instanceID: instanceID,
                                                artifact: artifact,
                                                capabilities: capabilities,
                                                viewerID: session.context["userId"] as? String ?? ""))
            return .started
        } catch {
            MXLog.error("[SpiralApp] could not mount \(instanceID): \(error)")
            return SpiralAppInstance.isInterrupted(error) ? .interrupted : .refused
        }
    }

    /// Whether this failure says "someone else took the slot" rather than
    /// "this app will not run".
    ///
    /// Both arrive as a `WKError` carrying a JavaScript message, so the text is
    /// what there is to read. Brittle, and named here once so it is brittle in
    /// exactly one place.
    private static func isInterrupted(_ error: Error) -> Bool {
        let description = String(describing: error)
        return description.contains(SpiralAppShellContract.abandoned)
            || description.contains("no longer reachable")
    }

    /// Take the app down and give the host back, then give up the session's
    /// share of the room subscription — in that order, so nothing the app
    /// does on its way out arrives after the session has stopped listening.
    ///
    /// The host is not destroyed: the pool unbinds it and keeps its shell warm
    /// for the next app. Whether it is actually kept is the pool's call.
    func stop() async {
        guard !isStopped else { return }
        isStopped = true
        forwarding = nil
        await pool.release(host)
        session.stop()
    }

    /// Like `stop`, but the host is destroyed rather than given back.
    ///
    /// For a host whose web content process the system has killed: there is
    /// no shell left in it to keep warm, and parking it would hand the next
    /// app a web view that will never paint.
    func discard() async {
        guard !isStopped else { return }
        isStopped = true
        forwarding = nil
        host.destroy()
        session.stop()
    }
}

/// How a post is presented, as the app is told (`viewport.changed`).
enum SpiralAppViewportMode: String {
    /// A chat bubble: small, fixed, never scrolls.
    case row
    /// The full-screen viewer: the app may scroll its own overflow.
    case expanded
}
