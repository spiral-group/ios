//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.5): one pooled web view, warmed
// with the trusted shell.
//
// The shell document is loaded ONCE and kept. Apps come and go inside it as
// sandboxed iframes, so mounting the next post costs an iframe rather than a
// page load — which is what makes "render immediately, no tap" affordable at
// three live posts.
//
// Reusing a web view across mutually untrusted apps is only safe because the
// untrusted code never touches the web view itself: it lives in a
// single-use frame whose destruction takes its whole JavaScript realm with
// it. Spike item 9 exists to prove that claim rather than assume it.
//
// SECURITY POSTURE — inverted from the Element Call host this borrows its
// shape from, because that code was trusted first-party and this is not:
//
//   file access                off (never set allowFileAccessFromFileURLs)
//   persistent storage         off (.nonPersistent data store)
//   inspectable                DEBUG only
//   navigation                 anything but spiral-app:// is cancelled
//   http(s) subresources       blocked by a content rule list, second layer
//   bridge                     main frame only, checked per message
//

import Combine
import Foundation
import Network
import SpiralAppShell
import WebKit

/// What the registry needs of a host.
///
/// Exists so the registry's policy — arming, eviction, the pool cap — can be
/// tested without standing up real web views, which would make every such test
/// depend on WebKit's scheduling rather than on the policy.
@MainActor
protocol SpiralAppHostProtocol: AnyObject {
    /// The view to place in a timeline row.
    var containerView: UIView { get }
    /// Wait for the shell to be warm, within a deadline. A host that can't
    /// get there has told `onContentProcessDied` as well, and is finished.
    func waitUntilReady() async throws
    /// Point the bridge at the session that owns this mount.
    ///
    /// A host outlives any one app now that they are pooled, so the binding
    /// that used to happen at construction happens here, per mount. The
    /// invariant it protects is unchanged: an app may only ever see the state
    /// of the post it is mounted on. `unmount()` unbinds BEFORE it destroys
    /// the frame, so there is no moment at which a parked host can answer
    /// from a session it no longer serves.
    func bind(_ handler: @escaping SpiralAppMethodHandler)
    func mount(_ mount: SpiralAppMount) async throws
    /// Tell a running app something it did not ask for — a state change made by
    /// someone else, or a warning that it is about to be torn down.
    func push(_ message: [String: Any]) async
    func unmount() async
    func destroy()
    /// A picture of what the app shows now, for its row to stand in with.
    ///
    /// Asked for at once rather than awaited, because the moment to take it is
    /// the one just before the view leaves its window. Answers nil when there
    /// is nothing to take, and always answers.
    func takeSnapshot(_ completion: @escaping (UIImage?) -> Void)
    /// Wait for the page to draw after coming back to a window. False means it
    /// didn't in time: a page that doesn't draw isn't running.
    func waitForPaint() async -> Bool
    /// Wait for the page to have laid itself out at `size` and drawn that:
    /// the host's view changes size when an app moves between the viewer and
    /// its row, and the page hears of it a frame or more later. False means it
    /// didn't draw in time.
    func waitForLayout(_ size: CGSize) async -> Bool
    /// Called when the system kills this host's web content process.
    ///
    /// On the protocol rather than only on the concrete host because the
    /// registry's policy for a dead app is policy, and policy is what the
    /// fake exists to let tests drive.
    var onContentProcessDied: (@MainActor () -> Void)? { get set }
}

/// Words the shell and the host both have to know.
///
/// Mirrored from `spiral-app-shell/src/shell/runtime.ts`. A string shared
/// across a language boundary is a contract with nothing to enforce it, so it
/// lives in one place on each side and is named in both.
nonisolated enum SpiralAppShellContract {
    /// A mount that a newer mount replaced. Not a broken app.
    static let abandoned = "spiral-mount-abandoned"
}

/// What can go wrong in a host, beyond what WebKit itself reports.
enum SpiralAppHostError: Error {
    /// The shell did not answer in time: a mount (`mountDeadline`), a paint,
    /// a status question.
    case timedOut
    /// The shell's document failed to load, or `__spiralShell` never came.
    case shellUnavailable
    /// The host was given back while a mount waited for it. Not a broken app.
    case unmountedWhileWaiting
    /// The artifact's manifest asks for a runtime this build does not carry.
    case newerRuntime
}

@MainActor
final class SpiralAppWebViewHost: NSObject, SpiralAppHostProtocol {
    /// The view to place in a timeline row. Never add the web view itself to
    /// a cell: cells are recycled and would take it down with them.
    let containerView = UIView(frame: .zero)

    /// How far the shell has got.
    private enum Shell {
        case loading
        /// `window.__spiralShell` exists, and a mount can be accepted.
        case ready
        /// It never will. Nothing goes back to `.loading`: the host is finished.
        case unavailable
    }

    private var shell = Shell.loading

    /// See the protocol. Set by the instance that owns this host.
    var onContentProcessDied: (@MainActor () -> Void)?

    /// Where bridge calls go. Swapped by `bind`/`unmount`; the bridge itself
    /// is registered once and calls through this indirection, so the web
    /// view's script-handler registration never has to change.
    private var boundHandler: SpiralAppMethodHandler = SpiralAppWebViewHost.unboundHandler

    private static let unboundHandler: SpiralAppMethodHandler = { _, _, _ in
        SpiralAppBridge.failure(code: "gone", message: "this app is no longer mounted")
    }

    private var webView: WKWebView!
    private let schemeHandler: SpiralAppSchemeHandler
    private var mounted: SpiralAppMount?
    /// Counted so a mount can tell it was given back while it waited.
    private var unmounts = 0
    private var readyContinuations: [CheckedContinuation<Void, Error>] = []
    private let readyDeadline: Duration

    /// Shared so WebKit may collocate the WebContent processes of several
    /// hosts. Modern WebKit decides process reuse largely from the DATA
    /// STORE, so that is shared too — one non-persistent store for every
    /// host in the process. Nothing an app does reaches storage anyway: it
    /// runs in an opaque-origin frame, which has none. Whether WebKit does
    /// collocate is measured (`ps | grep WebKit.WebContent`), not assumed.
    private static let sharedProcessPool = WKProcessPool()
    private static let sharedDataStore: WKWebsiteDataStore = {
        let store = WKWebsiteDataStore.nonPersistent()
        store.proxyConfigurations = [noNetwork]
        return store
    }()

    /// Every connection these web views open goes to a proxy that is not
    /// there, on this device's own loopback, and fails.
    ///
    /// The one network control a post cannot reach and WebKit cannot route
    /// around. A script-clicked `target=_blank` link made WebKit preconnect
    /// to its host — TCP, and over https a ClientHello naming it — inside the
    /// web content process, before the sandbox refused the popup and without
    /// asking either delegate (corpus F1). CSP, the content rule list and the
    /// navigation policy all sit above that. Through a proxy the host name
    /// is the proxy's to resolve, so no DNS query leaves either. Nothing here
    /// needs the network: every byte comes from the scheme handler.
    ///
    /// A host on loopback is never proxied (the system's rule, measured by
    /// the corpus): `linkGuardScript` keeps the link from being followed.
    private static let noNetwork: ProxyConfiguration = {
        var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: "127.0.0.1", port: 1))
        proxy.allowFailover = false
        return proxy
    }()

    /// Compiled once; blocks every http(s) subresource for these web views.
    /// Defence in depth behind `connect-src 'none'`: the custom scheme means
    /// WebKit has no origin to load from anyway, and CSP already refuses, so
    /// this is the third independent "no".
    private static var blockNetworkRuleList: WKContentRuleList?

    /// A host bound to one handler for its whole life. For the spike and the
    /// harness, which never pool.
    convenience init(allowsSpikeProbe: Bool = false,
                     methodHandler: @escaping SpiralAppMethodHandler) {
        self.init(allowsSpikeProbe: allowsSpikeProbe)
        bind(methodHandler)
    }

    /// An unbound host. Answers every bridge call with `gone` until `bind`.
    init(allowsSpikeProbe: Bool = false, readyDeadline: Duration = .seconds(10)) {
        schemeHandler = SpiralAppSchemeHandler(allowsSpikeProbe: allowsSpikeProbe)
        self.readyDeadline = readyDeadline
        super.init()

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: SpiralAppScheme.scheme)
        configuration.processPool = Self.sharedProcessPool
        // Nothing an app does may outlive its mount, and nothing may be
        // shared between two apps through storage.
        configuration.websiteDataStore = Self.sharedDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Text interaction stays ON. It was off, to kill the selection
        // magnifier over buttons — but the same switch kills the caret and the
        // keyboard in a text field, and a post with a field is a post that
        // cannot be typed into (measured 2026-09-16: a counter with a step
        // field never brought the keyboard up). The kit's stylesheet does the
        // narrow thing — `user-select: none` on the surface, back on for
        // fields — and CSS can tell a button from a field where this cannot.
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.suppressesIncrementalRendering = false

        let controller = WKUserContentController()

        // Both handlers live in an ISOLATED world, so page-world code — which
        // is where an artifact runs — has no `window.webkit` for them. See
        // SpiralAppContentWorld for why this is two controls rather than one.
        // The bridge captures `self` weakly and reads the CURRENT binding on
        // every call, which is what lets one web view serve many apps in turn.
        controller.addScriptMessageHandler(SpiralAppBridge { [weak self] method, args, userActivation in
            guard let self else {
                return await Self.unboundHandler(method, args, userActivation)
            }
            return await boundHandler(method, args, userActivation)
        },
        contentWorld: SpiralAppContentWorld.host,
        name: SpiralAppBridge.handlerName)
        controller.add(SpiralAppConsoleRelay(),
                       contentWorld: SpiralAppContentWorld.host,
                       name: SpiralAppConsoleRelay.handlerName)

        // Carries requests between the page world and the isolated one.
        // Main frame only: an artifact's frame gets no relay at all.
        controller.addUserScript(WKUserScript(source: SpiralAppContentWorld.relayScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true,
                                              in: SpiralAppContentWorld.host))

        // No link may be followed from a post, by a tap or by its script, in
        // any frame: see `linkGuardScript`. Before any page script runs, so
        // the post never sees what it replaces.
        controller.addUserScript(WKUserScript(source: Self.linkGuardScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false,
                                              in: .page))

        // No WebRTC in any frame: see `webRTCRemovalScript`.
        controller.addUserScript(WKUserScript(source: Self.webRTCRemovalScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false,
                                              in: .page))

        // No clipboard in any frame: see `clipboardRemovalScript`.
        controller.addUserScript(WKUserScript(source: Self.clipboardRemovalScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false,
                                              in: .page))

        // Mirror the web view's console into MXLog. A CSP refusal or a failed
        // module load is reported there and nowhere else, so without this a
        // broken shell looks identical to a silent one — which cost an hour
        // the first time it happened.
        controller.addUserScript(WKUserScript(source: Self.consoleForwardingScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true,
                                              in: .page))

        configuration.userContentController = controller

        #if SPIRAL_TIMELINE_BENCH // AGENT-PLATFORM (Brief 0083, question 359): what a scroll costs in web views.
        TimelineBenchProbe.shared.webViewsMade += 1
        #endif
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // The timeline owns scrolling. A web view that scrolls inside a
        // scrolling list fights it for gestures.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        // `isScrollEnabled = false` stops the reader, not WebKit: on focusing
        // a text field it scrolls the content to reveal the field, and the
        // app slid up inside its row. The delegate puts it back. The row is
        // sized from `aspect` and the app fits it, so there is never
        // anything to reveal.
        webView.scrollView.delegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false

        #if DEBUG
        webView.isInspectable = true
        #endif

        containerView.backgroundColor = .clear
        containerView.addMatchedSubview(webView)

        Task { await installContentRules() }
        webView.load(URLRequest(url: SpiralAppScheme.shellDocumentURL))
    }

    /// Says so when a host actually goes.
    ///
    /// Kept rather than removed after it answered its question: a `WKWebView`
    /// surviving its owner is invisible from inside this process — the cost is
    /// a WebContent process, which our own footprint does not count — so this
    /// line and `ps | grep WebKit.WebContent` are the only two ways to see it.
    deinit {
        MXLog.info("[SpiralApp] web view host gone")
    }

    // MARK: - Lifecycle

    func bind(_ handler: @escaping SpiralAppMethodHandler) {
        boundHandler = handler
    }

    /// Wait until the shell is warm. Returns immediately once it is.
    ///
    /// "Warm" means `window.__spiralShell` exists, which is **later** than
    /// `didFinish`: the shell is an ES module, so the document finishes
    /// loading before the module graph has evaluated. Waiting on navigation
    /// alone raced the global into existence and produced
    /// `undefined is not an object (evaluating 'window.__spiralShell.mount')`.
    ///
    /// Bounded: `didFinish` may never come, and a post waiting here held a
    /// slot from every other post in the room for as long as it stayed.
    func waitUntilReady() async throws {
        switch shell {
        case .ready:
            return
        case .unavailable:
            throw SpiralAppHostError.shellUnavailable
        case .loading:
            break
        }

        let deadline = readyDeadline
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                readyContinuations.append(continuation)
                // A shell still loading at the deadline has failed; failing it
                // answers every waiter, this one included.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: deadline)
                    self?.shellDidFail()
                }
            }
        } catch {
            MXLog.error("[SpiralApp] the shell never became ready — check the web console relay")
            shellDidFail()
            throw SpiralAppHostError.shellUnavailable
        }
    }

    /// Navigation finished; now wait for the module to install its API.
    private func waitForShellAPI() async {
        let deadline = ContinuousClock.now + readyDeadline
        while shell == .loading, ContinuousClock.now < deadline {
            let installed = try? await callShell("return typeof window.__spiralShell", deadline: .seconds(1))
            if installed == "object" {
                settleShell(.ready)
                return
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        shellDidFail()
    }

    /// The shell is not coming, which is a death like a killed process: this
    /// host has nothing to mount into, and parking it would poison the pool.
    private func shellDidFail() {
        guard shell == .loading else { return }
        settleShell(.unavailable)
        onContentProcessDied?()
    }

    private func settleShell(_ outcome: Shell) {
        shell = outcome
        let waiting = readyContinuations
        readyContinuations.removeAll()
        for continuation in waiting {
            if outcome == .ready {
                continuation.resume()
            } else {
                continuation.resume(throwing: SpiralAppHostError.shellUnavailable)
            }
        }
    }

    /// Wait until the container is in a window, briefly.
    ///
    /// A web view that is not in a window has nothing to paint into (§5.19),
    /// and the row adopts this container on its next SwiftUI update — one
    /// frame, usually. A warm host from the pool mounts faster than that, so
    /// without this the app painted into a detached view, reported itself
    /// painted, the card lifted, and the row showed a grey rectangle. Bounded
    /// so a host nobody adopts — evicted again before its row settled — still
    /// mounts rather than hangs; the shell's own paint timeout takes over.
    private func waitUntilInWindow() async {
        let deadline = Date().addingTimeInterval(1)
        while containerView.window == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    /// Replace whatever is running with `mount`.
    ///
    /// The previous app's frame is destroyed by the shell before the new one
    /// is created, so two artifacts never share a realm.
    func mount(_ mount: SpiralAppMount) async throws {
        // The event's `runtime` is checked before a row mounts, but the
        // artifact says its own, and code written for a newer runtime must
        // not run under this one (corpus F6, decision 96).
        guard SpiralAppPost.supportedRuntimes.contains(mount.artifact.runtimeVersion) else {
            throw SpiralAppHostError.newerRuntime
        }
        let unmountsBefore = unmounts
        try await waitUntilReady()
        await waitUntilInWindow()
        // Given back while it waited; the next app may already have this host.
        guard unmounts == unmountsBefore else { throw SpiralAppHostError.unmountedWhileWaiting }

        // Registering is what makes the artifact reachable at all; an
        // unregistered origin is refused by the handler.
        #if SPIRAL_TIMELINE_BENCH // AGENT-PLATFORM (Brief 0083, question 359): what a scroll costs in mounts.
        TimelineBenchProbe.shared.mounts += 1
        #endif
        schemeHandler.register(mount.artifact)
        mounted = mount

        let request: [String: Any] = [
            "instanceId": mount.instanceID,
            "documentUrl": mount.documentURL.absoluteString,
            "capabilities": mount.capabilities.map(\.rawValue),
            "runtimeVersion": mount.artifact.runtimeVersion,
            "viewerId": mount.viewerID,
            "language": mount.language
        ]
        // `callAsyncJavaScript`, not `evaluateJavaScript`, because `mount`
        // resolves when the app has DRAWN and only the former waits for a
        // promise. `evaluateJavaScript` would return the moment the shell
        // accepted the artifact, while the frame was still compiling it —
        // and the row would uncover an empty rectangle and call it an app.
        //
        // BOUNDED HERE, not only in the shell.
        //
        // This comment used to say "the shell's own timeout bounds this". The
        // shell does carry one — and `destroy()` cleared it without settling
        // the promise, so a mount replaced while starting waited for ever:
        // 35 of 411 in one session, each a suspended task and a post stuck
        // behind its card, with nothing in any log to say so. The shell is
        // fixed; this exists because a bound that lives in another layer is a
        // bound you are trusting, not one you have.
        do {
            _ = try await callShell("await window.__spiralShell.mount(request)", arguments: ["request": request], deadline: Self.mountDeadline)
        } catch {
            // A LOST ANSWER IS NOT A FAILED MOUNT.
            //
            // `Completion handler for function call is no longer reachable` is
            // WebKit saying the reply could not be delivered — the page churned
            // under it — NOT that the call did not happen. Measured: an app
            // painted its counter, its buttons worked, and the row kept the
            // card on top of it for ever, because the answer went missing and
            // this threw.
            //
            // The shell knows what it is running, so ask it rather than
            // guessing from the absence of a reply.
            //
            // Bounded too (corpus F3): a post spinning before its first paint
            // blocks the shell as well, and an unbounded question here hung
            // the mount, and its row, for good.
            guard await isShowing(mount.instanceID) else { throw error }
            MXLog.info("[SpiralApp] \(mount.instanceID) lost its mount reply but is running — continuing")
        }
    }

    /// Longest a mount may take before the host stops waiting on it.
    ///
    /// Generous: the shell's own paint timeout is 5 s, so anything shorter
    /// would cut off artifacts the shell is still giving a fair chance. This
    /// is the backstop for a reply that never comes at all, not a performance
    /// budget.
    private static let mountDeadline = Duration.seconds(8)

    /// Whether the shell says it is running this instance right now. No
    /// answer within a second is "no": a shell that silent is not running it.
    private func isShowing(_ instanceID: String) async -> Bool {
        guard let json = try? await callShell("return JSON.stringify(window.__spiralShell.status())", deadline: .seconds(1)),
              let status = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return false
        }
        return status["mounted"] as? Bool == true && status["instanceId"] as? String == instanceID
    }

    /// Run `body` (a function body) in the shell's page, answering within
    /// `deadline` with the string it returns, if any.
    ///
    /// WebKit keeps the reply handler until the page answers, and a post
    /// spinning in `for (;;)` blocks the shell, so it never does. The handler
    /// therefore holds nothing of this host — a latch and the continuation —
    /// and a host destroyed while waiting goes, its web view and page with it
    /// (corpus F7). Awaiting WebKit's `async` form held the host for ever, and
    /// the spinning page kept its process after `destroy()`.
    ///
    /// The JavaScript is not cancelled; only the waiting stops.
    private func callShell(_ body: String, arguments: [String: Any] = [:], deadline: Duration) async throws -> String? {
        final class Latch {
            var isClosed = false
        }

        let latch = Latch()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String?, Error>) in
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                guard !latch.isClosed else { return }
                latch.isClosed = true
                switch result {
                case .success(let value):
                    continuation.resume(returning: value as? String)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: deadline)
                guard !latch.isClosed else { return }
                latch.isClosed = true
                continuation.resume(throwing: SpiralAppHostError.timedOut)
            }
        }
    }

    /// Deliver an unsolicited message to the running app.
    ///
    /// One-way in intent: a push the app never reads must not stall the
    /// caller, and there is nothing useful to do about it if it does.
    ///
    /// The message is a BOUND ARGUMENT, exactly as `mount` passes its
    /// request. It used to be serialised and interpolated into the source
    /// text of a fresh JS program — which was narrowly safe only because
    /// JSON has been a subset of JS expressions since ES2019, a detail
    /// nobody wrote down and nothing enforced. What travels this way is
    /// state written by other people's apps on other people's devices, and
    /// it lands in the PAGE world of the trusted shell — the one realm that
    /// holds the relay to native. A binding cannot be read as syntax, so the
    /// question stops being "is this encoder safe" and stops being asked.
    ///
    /// It also stops compiling a new program per message: this runs perhaps
    /// once a second today, and a live channel would ask for far more.
    ///
    /// Not awaited: an app spinning in `while (true) {}` never lets the reply
    /// come, and a caller suspended on it would keep this host — and its web
    /// view — alive after it was destroyed (N1). The reply's handler holds
    /// nothing.
    func push(_ message: [String: Any]) async {
        guard mounted != nil else { return }

        webView.callAsyncJavaScript("window.__spiralShell.push(message);",
                                    arguments: ["message": message],
                                    in: nil,
                                    in: .page,
                                    completionHandler: nil)
    }

    /// Destroy the running app. The shell stays warm for the next one.
    ///
    /// Unbinds FIRST. The frame is torn down asynchronously, and a call that
    /// was in flight when the app was told to go must land on `gone`, never on
    /// the session this host is about to stop serving.
    ///
    /// Bounded, and waited for through a handler that holds nothing (M3, N1):
    /// an app spinning in `while (true) {}` blocks the shell too, and an
    /// `await` on the reply would hold this host and its web view for as long
    /// as the reply never comes — past `destroy()`, for ever.
    func unmount() async {
        unmounts += 1
        boundHandler = Self.unboundHandler
        guard let mounted else { return }

        final class Latch {
            var isClosed = false
        }
        let latch = Latch()
        let deadline = Self.unmountDeadline
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.__spiralShell.unmount(); true") { _, _ in
                guard !latch.isClosed else { return }
                latch.isClosed = true
                continuation.resume()
            }
            Task { @MainActor in
                try? await Task.sleep(for: deadline)
                guard !latch.isClosed else { return }
                latch.isClosed = true
                continuation.resume()
            }
        }
        schemeHandler.unregister(host: mounted.artifact.originHost)
        self.mounted = nil
    }

    func takeSnapshot(_ completion: @escaping (UIImage?) -> Void) {
        guard let instanceID = mounted?.instanceID, containerView.window != nil, webView.bounds.width > 0 else {
            if let instanceID = mounted?.instanceID {
                SpiralAppReturnTrace.step(instanceID, "no snapshot — container in window=\(containerView.window != nil) width=\(Int(webView.bounds.width))")
            }
            completion(nil)
            return
        }

        let configuration = WKSnapshotConfiguration()
        // What is on screen now: waiting for the next update could outlast the
        // window, and a post mid-animation has no better frame to offer.
        configuration.afterScreenUpdates = false
        // In points, at the screen's scale. Twice the row's size is enough for
        // a picture on show for a moment, and a 3x one is over twice the memory.
        let scale = webView.traitCollection.displayScale
        configuration.snapshotWidth = NSNumber(value: webView.bounds.width * min(scale, 2) / scale)

        final class Latch {
            var isClosed = false
        }
        let latch = Latch()
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard !latch.isClosed else { return }
            latch.isClosed = true
            // A late picture of the post that took this host over isn't this post's.
            completion(self?.mounted?.instanceID == instanceID ? image : nil)
        }
        Task { @MainActor in
            try? await Task.sleep(for: Self.snapshotDeadline)
            guard !latch.isClosed else { return }
            latch.isClosed = true
            SpiralAppReturnTrace.step(instanceID, "snapshot deadline passed")
            completion(nil)
        }
    }

    /// Runs in the shell's own page, which the app's frame can't reach. Two
    /// frames, because the first may be the one that was already on its way.
    func waitForPaint() async -> Bool {
        guard mounted != nil else { return false }

        do {
            _ = try await callShell("await new Promise(done => requestAnimationFrame(() => requestAnimationFrame(done)))", deadline: Self.paintDeadline)
            return true
        } catch SpiralAppHostError.timedOut {
            return false
        } catch {
            // WebKit lost the reply, which says the page is there.
            return true
        }
    }

    func waitForLayout(_ size: CGSize) async -> Bool {
        guard mounted != nil else { return false }

        // Every frame until the shell's page has the new size, at most two
        // seconds' worth, then two more frames for the app inside it to draw.
        let script = """
        return await new Promise(done => {
            let frames = 0
            const settled = () => Math.abs(innerWidth - width) <= 1 && Math.abs(innerHeight - height) <= 1
            const tick = () => {
                frames += 1
                if (settled() || frames > 120) {
                    requestAnimationFrame(() => requestAnimationFrame(() => done(`${innerWidth}x${innerHeight} ${settled()} ${frames}`)))
                } else {
                    requestAnimationFrame(tick)
                }
            }
            tick()
        })
        """
        do {
            let answer = try await callShell(script, arguments: ["width": size.width, "height": size.height], deadline: Self.paintDeadline)
            #if DEBUG || SPIRAL_STAGING
            if let instanceID = mounted?.instanceID {
                SpiralAppReturnTrace.step(instanceID, "page laid out at \(answer ?? "?") (asked \(Int(size.width))x\(Int(size.height)), settled, frames)")
            }
            #endif
            return true
        } catch SpiralAppHostError.timedOut {
            return false
        } catch {
            return true
        }
    }

    private static let snapshotDeadline = Duration.milliseconds(500)
    /// The same patience as an unmount's: a page silent for this long is wedged.
    private static let paintDeadline = Duration.seconds(2)

    /// The host's own bound on an unmount, a second past the pool's (2 s), so
    /// the pool always decides first that a silent host is wedged and destroys it.
    private static let unmountDeadline = Duration.seconds(3)

    /// Tear the host down completely. After this the instance is unusable.
    /// The web view goes with this host once nothing holds the host: its
    /// page is closed then, and its WebContent process ends unless another
    /// host's page shares it (the process pool is shared).
    func destroy() {
        boundHandler = Self.unboundHandler
        settleShell(.unavailable)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.removeFromSuperview()
        schemeHandler.unregisterAll()
        mounted = nil
    }

    // MARK: - Content rules

    private func installContentRules() async {
        if let existing = Self.blockNetworkRuleList {
            webView.configuration.userContentController.add(existing)
            return
        }

        // Deliberately scoped to http(s) rather than `.*`: a blanket block
        // would also refuse our own `spiral-app://` loads, and the point is
        // to deny the network while leaving the handler's answers alone.
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}}]
        """

        do {
            let list = try await WKContentRuleListStore.default()
                .compileContentRuleList(forIdentifier: "SpiralAppBlockNetwork", encodedContentRuleList: rules)
            if let list {
                Self.blockNetworkRuleList = list
                webView.configuration.userContentController.add(list)
            }
        } catch {
            // Not fatal: CSP and the scheme handler are the primary controls
            // and neither depends on this. Worth surfacing, because losing a
            // layer silently is how defence in depth erodes.
            MXLog.error("[SpiralApp] could not compile the network block list: \(error)")
        }
    }

    /// Refuses every activation of a link (`a`, `area`, SVG `a`).
    ///
    /// A script-clicked `target=_blank` link made WebKit preconnect to its
    /// host inside the web content process, before the frame's sandbox
    /// refused the popup and without asking either delegate (corpus F1). The
    /// data store's dead proxy keeps that from reaching any host off the
    /// phone; this keeps it from being attempted at all, loopback included.
    /// A post has no use for a link: it has no network and no navigation.
    ///
    /// It runs in the post's own realm, so it is built to stay there: the
    /// replaced methods are non-writable and non-configurable, and every
    /// built-in it relies on is captured before the post's first line, so
    /// nothing the post redefines later is consulted. Three doors:
    ///   - `click()` on an element that is a link or inside one, or inside a
    ///     label that holds one or whose control (`for`) is inside one — a
    ///     label forwards its click to its control;
    ///   - `dispatchEvent` of any event on such an element — a synthetic
    ///     click need not be cancelable, and a detached link's event never
    ///     reaches the window. A container that merely holds a link is not
    ///     refused: its events bubble up, never down into the link;
    ///   - a capturing listener on the window that cancels a real tap.
    /// Shadow roots are all open, so neither the walk nor a tap's path can
    /// miss a link inside one.
    private static let linkGuardScript = """
    (function () {
      'use strict';
      var apply = Reflect.apply;
      var describe = Object.getOwnPropertyDescriptor;
      var lock = function (owner, name, value) {
        Object.defineProperty(owner, name, { value: value, writable: false, configurable: false, enumerable: true });
      };
      var get = function (owner, name) { return describe(owner, name).get; };
      var nodeType = get(Node.prototype, 'nodeType');
      var parentNode = get(Node.prototype, 'parentNode');
      var localName = get(Element.prototype, 'localName');
      var shadowHost = get(ShadowRoot.prototype, 'host');
      var elementSlot = get(Element.prototype, 'assignedSlot');
      var textSlot = get(Text.prototype, 'assignedSlot');
      var querySelector = Element.prototype.querySelector;
      var composedPath = Event.prototype.composedPath;
      var preventDefault = Event.prototype.preventDefault;
      var nativeDispatch = EventTarget.prototype.dispatchEvent;
      var nativeClick = HTMLElement.prototype.click;
      var nativeAttachShadow = Element.prototype.attachShadow;
      var assign = Object.assign;
      var refuse = function () { throw new TypeError('not available in a post'); };
      var isLink = function (node) {
        var name = apply(localName, node, []);
        return name === 'a' || name === 'area';
      };
      var labelControl = get(HTMLLabelElement.prototype, 'control');
      // A label forwards its click to its control, wherever that is: inside
      // the label or named by `for`, inside a link either way.
      var labelReachesLink = function (label) {
        if (apply(querySelector, label, ['a, area'])) return true;
        var control = null;
        try { control = apply(labelControl, label, []); } catch (notALabel) { return false; }
        return !!control && touchesLink(control, true);
      };
      // The event path's own walk: a slot before a parent, a shadow root's host.
      var touchesLink = function (target, fromLabel) {
        var node = target;
        try {
          for (var depth = 0; node; depth++) {
            if (depth > 4096) return true;
            var type = apply(nodeType, node, []);
            if (type === 1 && isLink(node)) return true;
            if (type === 1 && !fromLabel && apply(localName, node, []) === 'label' && labelReachesLink(node)) return true;
            var next = type === 1 ? apply(elementSlot, node, []) : type === 3 ? apply(textSlot, node, []) : null;
            if (!next) next = apply(parentNode, node, []);
            if (!next && type === 11) {
              try { next = apply(shadowHost, node, []); } catch (notShadow) { next = null; }
            }
            node = next;
          }
        } catch (notANode) {
          return false;
        }
        return false;
      };
      // A closed shadow root hides its slots from the walk below and its
      // links from a tap's path, so every root is open. The parser's ways to
      // a closed one, declarative shadow DOM, are not available.
      lock(Element.prototype, 'attachShadow', function attachShadow(init) {
        return apply(nativeAttachShadow, this, [assign({}, init, { mode: 'open' })]);
      });
      [[Element.prototype, 'setHTMLUnsafe'], [ShadowRoot.prototype, 'setHTMLUnsafe'], [Document, 'parseHTMLUnsafe'],
       [Document.prototype, 'write'], [Document.prototype, 'writeln'], [Document.prototype, 'open']].forEach(function (entry) {
        if (entry[1] in entry[0]) lock(entry[0], entry[1], refuse);
      });
      lock(HTMLElement.prototype, 'click', function click() {
        if (touchesLink(this)) return;
        return apply(nativeClick, this, arguments);
      });
      lock(EventTarget.prototype, 'dispatchEvent', function dispatchEvent(event) {
        if (touchesLink(this)) return false;
        return apply(nativeDispatch, this, arguments);
      });
      window.addEventListener('click', function (event) {
        var path = apply(composedPath, event, []);
        for (var i = 0; i < path.length; i++) {
          try { if (apply(nodeType, path[i], []) === 1 && isLink(path[i])) { apply(preventDefault, event, []); return; } } catch (notANode) {}
        }
      }, true);
    })();
    """

    /// Removes WebRTC from every frame, for good.
    ///
    /// CSP has no directive for it, and its STUN and TURN traffic goes over
    /// WebKit's own UDP and TCP sockets, not the data store's proxy. The
    /// shell's `harden.ts` deletes the constructors in the post's document
    /// only; a frame the post makes (`srcdoc`, `data:`) would arrive with
    /// pristine ones. This runs in every frame before any page script, and
    /// leaves each name a non-writable, non-configurable `undefined` that
    /// nothing can put back.
    private static let webRTCRemovalScript = """
    (function () {
      'use strict';
      var names = ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCRtpSender', 'RTCRtpReceiver',
                   'RTCRtpTransceiver', 'RTCIceCandidate', 'RTCSessionDescription', 'RTCCertificate', 'RTCDtlsTransport',
                   'RTCIceTransport', 'RTCSctpTransport', 'RTCDTMFSender', 'RTCRtpScriptTransform', 'RTCEncodedAudioFrame',
                   'RTCEncodedVideoFrame', 'RTCPeerConnectionIceEvent', 'RTCDataChannelEvent', 'RTCTrackEvent', 'RTCError'];
      Object.getOwnPropertyNames(window).forEach(function (name) {
        if (/^(webkit)?RTC/.test(name) && names.indexOf(name) < 0) names.push(name);
      });
      names.forEach(function (name) {
        try { delete window[name]; } catch (stays) {}
        try {
          Object.defineProperty(window, name, { value: undefined, writable: false, configurable: false, enumerable: false });
        } catch (locked) {}
      });
    })();
    """

    /// Takes the clipboard away from every frame, for good (corpus F11).
    ///
    /// After a real tap a post's `navigator.clipboard.writeText` wrote the
    /// pasteboard on a device: a fake "copy code" button could hand the
    /// person something else. No post needs the clipboard and neither does
    /// the shell, so this runs in every frame, the shell's included, before
    /// any page script, built like the link guard:
    ///   - `navigator.clipboard`, `Clipboard` and `ClipboardItem` become
    ///     locked `undefined`s, on the prototype and the instance, so nothing
    ///     can put them back;
    ///   - `execCommand` returns false for copy, cut and every paste variant
    ///     and runs every other command; `queryCommandSupported` and
    ///     `queryCommandEnabled` say false for them;
    ///   - copy, cut and paste events stop at the window before any listener
    ///     of the post's, so it can't rewrite `clipboardData` or cancel the
    ///     copy, and `clipboardData` reads null. (The post still owns its DOM,
    ///     so what the person selects and copies is the post's text — that is
    ///     web content, not the clipboard API, DEBT.) The default
    ///     action is left alone: the person's own Copy, Cut and Paste in a
    ///     text field still work.
    private static let clipboardRemovalScript = """
    (function () {
      'use strict';
      var apply = Reflect.apply;
      var define = Object.defineProperty;
      var toString = String;
      var toLowerCase = String.prototype.toLowerCase;
      var trim = String.prototype.trim;
      var stopImmediatePropagation = Event.prototype.stopImmediatePropagation;
      var lock = function (owner, name, value) {
        define(owner, name, { value: value, writable: false, configurable: false, enumerable: true });
      };
      var remove = function (owner, name) {
        try { delete owner[name]; } catch (stays) {}
        try { define(owner, name, { value: undefined, writable: false, configurable: false, enumerable: false }); } catch (locked) {}
      };
      remove(Navigator.prototype, 'clipboard');
      remove(navigator, 'clipboard');
      remove(window, 'Clipboard');
      remove(window, 'ClipboardItem');

      var refused = Object.create(null);
      refused.copy = refused.cut = refused.paste = true;
      // One conversion to a primitive, so an object can't name one command
      // to the check and another to WebKit.
      var named = function (command) { return toString(command); };
      var startsWith = String.prototype.startsWith;
      // Every paste variant WebKit's editor knows (PasteAsPlainText,
      // PasteAndMatchStyle, PasteAsQuotation) is the same door as paste.
      var isRefused = function (name) {
        var folded = apply(trim, apply(toLowerCase, name, []), []);
        return refused[folded] === true || apply(startsWith, folded, ['paste']);
      };
      var nativeExecCommand = Document.prototype.execCommand;
      var nativeQuerySupported = Document.prototype.queryCommandSupported;
      var nativeQueryEnabled = Document.prototype.queryCommandEnabled;
      lock(Document.prototype, 'execCommand', function execCommand(command, showUI, value) {
        var name = named(command);
        if (isRefused(name)) return false;
        return apply(nativeExecCommand, this, arguments.length > 2 ? [name, showUI, value] : arguments.length > 1 ? [name, showUI] : [name]);
      });
      lock(Document.prototype, 'queryCommandSupported', function queryCommandSupported(command) {
        var name = named(command);
        return isRefused(name) ? false : apply(nativeQuerySupported, this, [name]);
      });
      lock(Document.prototype, 'queryCommandEnabled', function queryCommandEnabled(command) {
        var name = named(command);
        return isRefused(name) ? false : apply(nativeQueryEnabled, this, [name]);
      });

      // The window's capture phase comes first for every node in the
      // document, and this listener is the first one registered there.
      var stop = function (event) { apply(stopImmediatePropagation, event, []); };
      window.addEventListener('copy', stop, true);
      window.addEventListener('cut', stop, true);
      window.addEventListener('paste', stop, true);
      try {
        define(ClipboardEvent.prototype, 'clipboardData', { get: function () { return null; }, configurable: false, enumerable: true });
      } catch (noClipboardEvent) {}
    })();
    """

    /// Forwards console output and uncaught errors to the native side.
    ///
    /// Injected into every frame, including the sandboxed one, so a failure
    /// inside an untrusted app is diagnosable without reaching into it.
    private static let consoleForwardingScript = """
    (function () {
      var relay = function (level, args) {
        try {
          document.dispatchEvent(new CustomEvent('\(SpiralAppContentWorld.requestEvent)', {
            detail: {
              channel: 'console',
              body: {
                level: level,
                text: Array.prototype.map.call(args, function (a) {
                  if (typeof a === 'string') return a;
                  try { return JSON.stringify(a); } catch (e) { return String(a); }
                }).join(' ')
              }
            }
          }));
        } catch (e) { /* no relay in this frame */ }
      };
      ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
        var original = console[level];
        console[level] = function () {
          relay(level, arguments);
          if (original) original.apply(console, arguments);
        };
      });
      window.addEventListener('error', function (event) {
        relay('error', ['uncaught: ' + event.message + ' @ ' + event.filename + ':' + event.lineno]);
      });
      window.addEventListener('unhandledrejection', function (event) {
        relay('error', ['unhandled rejection: ' + event.reason]);
      });
      window.addEventListener('securitypolicyviolation', function (event) {
        relay('error', ['CSP blocked ' + event.blockedURI +
                        ' (directive: ' + event.violatedDirective + ')']);
      });
    })();
    """
}

/// Relays the web view's console into `MXLog`.
///
/// Message handlers are registered per content world and are reachable from
/// **every** frame, including a sandboxed opaque-origin one — the Brief 0066
/// probe confirmed `window.webkit.messageHandlers` is visible to an
/// untrusted app. So this relay tags where a line came from and truncates
/// it: an app that spams the log should be obvious and bounded, not silent.
final class SpiralAppConsoleRelay: NSObject, WKScriptMessageHandler {
    static let handlerName = "spiralAppConsole"

    /// Longest line accepted from the page. A hostile app would otherwise
    /// use the log as an unbounded write primitive.
    private static let maxLength = 2000

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let rawText = body["text"] as? String else { return }

        let origin = message.frameInfo.isMainFrame ? "shell" : "app"
        let text = rawText.count > Self.maxLength
            ? String(rawText.prefix(Self.maxLength)) + "… (truncated)"
            : rawText
        let level = body["level"] as? String ?? "log"

        switch level {
        case "error":
            MXLog.error("[SpiralApp/\(origin)] \(text)")
        case "warn":
            MXLog.warning("[SpiralApp/\(origin)] \(text)")
        default:
            MXLog.info("[SpiralApp/\(origin)] \(text)")
        }
    }
}

// MARK: - WKNavigationDelegate

extension SpiralAppWebViewHost: WKNavigationDelegate {
    // These arrive on the main actor, and `WKNavigationAction` is itself
    // main-actor isolated, so the whole extension stays with the target's
    // default MainActor isolation rather than hopping.
    /// Exactly two documents may ever load: the shell in the main frame, and
    /// a mounted artifact's synthesised page in its frame. Everything else —
    /// a new window, any other scheme, the shell or another post inside a
    /// frame (prior audit L2) — is cancelled. Checked here as well as in CSP
    /// because a navigation is not a subresource fetch.
    ///
    /// Not what stopped F1: a sandboxed frame's `_blank` click never reaches
    /// this delegate, and its preconnect left before any policy was asked.
    /// The proxy and the link guard are what stop that.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard isAllowed(navigationAction) else {
            MXLog.info("[SpiralApp] cancelled a navigation that is not the shell or a mounted post")
            return .cancel
        }
        return .allow
    }

    private func isAllowed(_ navigationAction: WKNavigationAction) -> Bool {
        guard let target = navigationAction.targetFrame,
              let url = navigationAction.request.url,
              url.scheme == SpiralAppScheme.scheme,
              let host = url.host,
              ["/", "/index.html"].contains(url.path.isEmpty ? "/" : url.path) else {
            return false
        }
        return target.isMainFrame ? host == SpiralAppScheme.shellHost : schemeHandler.isServing(host: host)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Only the shell document makes the host ready; an iframe load does
        // not come through here as a main-frame finish.
        if webView.url?.host == SpiralAppScheme.shellHost {
            Task { await waitForShellAPI() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MXLog.error("[SpiralApp] shell navigation failed: \(error)")
        shellDidFail()
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: any Error) {
        MXLog.error("[SpiralApp] shell provisional navigation failed: \(error)")
        shellDidFail()
    }

    /// The system killed this web view's content process.
    ///
    /// The one failure that looks like no failure: the view stays in the
    /// hierarchy, keeps its size, reports a window, and draws nothing ever
    /// again. Nothing else in `WKNavigationDelegate` fires, so without this
    /// the host cannot tell a dead app from a quiet one.
    ///
    /// iOS is documented to kill the content processes of web views it thinks
    /// are not being looked at, and a timeline can hold several at once — so
    /// this is not an edge case here, it is the normal cost of the design.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MXLog.error("[SpiralApp] the web content process died — the app is now a blank rectangle")
        onContentProcessDied?()
    }
}

// MARK: - UIScrollViewDelegate

extension SpiralAppWebViewHost: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.contentOffset != .zero else { return }
        scrollView.contentOffset = .zero
    }
}

// MARK: - WKUIDelegate

extension SpiralAppWebViewHost: WKUIDelegate {
    /// Refuse every attempt to open a window. `sandbox="allow-scripts"`
    /// without `allow-popups` should already prevent this; returning nil
    /// makes it true regardless of how the frame was configured.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }

    /// No app may take the camera or the microphone. v1 has no media
    /// capability at all, so this is unconditional.
    func webView(_ webView: WKWebView,
                 decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo,
                 type: WKMediaCaptureType) async -> WKPermissionDecision {
        .deny
    }
}
