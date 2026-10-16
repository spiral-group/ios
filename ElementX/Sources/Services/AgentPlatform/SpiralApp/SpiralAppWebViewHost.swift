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
    func waitUntilReady() async
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
    /// The shell never answered a mount. See `mountDeadline`.
    case mountTimedOut
}

@MainActor
final class SpiralAppWebViewHost: NSObject, SpiralAppHostProtocol {
    /// The view to place in a timeline row. Never add the web view itself to
    /// a cell: cells are recycled and would take it down with them.
    let containerView = UIView(frame: .zero)

    /// Fires when the shell has loaded and can accept a mount.
    private(set) var isReady = false

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
    private var readyContinuations: [CheckedContinuation<Void, Never>] = []

    /// Shared so WebKit may collocate the WebContent processes of several
    /// hosts. Modern WebKit decides process reuse largely from the DATA
    /// STORE, so that is shared too — one non-persistent store for every
    /// host in the process. Nothing an app does reaches storage anyway: it
    /// runs in an opaque-origin frame, which has none. Whether WebKit does
    /// collocate is measured (`ps | grep WebKit.WebContent`), not assumed.
    private static let sharedProcessPool = WKProcessPool()
    private static let sharedDataStore = WKWebsiteDataStore.nonPersistent()

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
    init(allowsSpikeProbe: Bool = false) {
        schemeHandler = SpiralAppSchemeHandler(allowsSpikeProbe: allowsSpikeProbe)
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

        // Mirror the web view's console into MXLog. A CSP refusal or a failed
        // module load is reported there and nowhere else, so without this a
        // broken shell looks identical to a silent one — which cost an hour
        // the first time it happened.
        controller.addUserScript(WKUserScript(source: Self.consoleForwardingScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true,
                                              in: .page))

        configuration.userContentController = controller

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
    func waitUntilReady() async {
        if isReady { return }

        await withCheckedContinuation { continuation in
            readyContinuations.append(continuation)
        }

        // Navigation finished; now wait for the module to install its API.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let installed = await (try? webView.evaluateJavaScript("typeof window.__spiralShell")) as? String
            if installed == "object" { return }
            try? await Task.sleep(for: .milliseconds(25))
        }

        MXLog.error("[SpiralApp] the shell never installed __spiralShell — check the web console relay")
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
        await waitUntilReady()
        await waitUntilInWindow()

        // Registering is what makes the artifact reachable at all; an
        // unregistered origin is refused by the handler.
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
            try await withTimeout(Self.mountDeadline) {
                _ = try await self.webView.callAsyncJavaScript("await window.__spiralShell.mount(request)",
                                                               arguments: ["request": request],
                                                               contentWorld: .page)
            }
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
            guard try await isShowing(mount.instanceID) else { throw error }
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

    /// Run `work`, or throw if it has not answered in time.
    ///
    /// The JavaScript call is NOT cancelled — `callAsyncJavaScript` does not
    /// answer to cancellation, so pretending otherwise would swap one silent
    /// wait for another. What this does is stop the CALLER waiting, which is
    /// the part that was leaving posts behind their cards.
    ///
    /// Same shape as the spike runner's `ReportWaiter`: whichever finishes
    /// first resumes, the other finds the latch closed and does nothing.
    private func withTimeout(_ deadline: Duration, _ work: @escaping @MainActor () async throws -> Void) async throws {
        final class Latch {
            var isClosed = false
        }

        let latch = Latch()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task { @MainActor in
                do {
                    try await work()
                    guard !latch.isClosed else { return }
                    latch.isClosed = true
                    continuation.resume()
                } catch {
                    guard !latch.isClosed else { return }
                    latch.isClosed = true
                    continuation.resume(throwing: error)
                }
            }

            Task { @MainActor in
                try? await Task.sleep(for: deadline)
                guard !latch.isClosed else { return }
                latch.isClosed = true
                continuation.resume(throwing: SpiralAppHostError.mountTimedOut)
            }
        }
    }

    /// Whether the shell says it is running this instance right now.
    ///
    /// `status()` is synchronous in the shell, so `evaluateJavaScript` is the
    /// right call here: there is no promise to wait for, and using the async
    /// form would reintroduce the very round trip that went missing.
    private func isShowing(_ instanceID: String) async throws -> Bool {
        let raw = try await webView.evaluateJavaScript("JSON.stringify(window.__spiralShell.status())")
        guard let json = raw as? String,
              let data = json.data(using: .utf8),
              let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return status["mounted"] as? Bool == true && status["instanceId"] as? String == instanceID
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
    func push(_ message: [String: Any]) async {
        guard mounted != nil else { return }

        _ = try? await webView.callAsyncJavaScript("window.__spiralShell.push(message);",
                                                   arguments: ["message": message],
                                                   contentWorld: .page)
    }

    /// Destroy the running app. The shell stays warm for the next one.
    ///
    /// Unbinds FIRST. The frame is torn down asynchronously, and a call that
    /// was in flight when the app was told to go must land on `gone`, never on
    /// the session this host is about to stop serving.
    func unmount() async {
        boundHandler = Self.unboundHandler
        guard let mounted else { return }
        _ = try? await webView.evaluateJavaScript("window.__spiralShell.unmount(); true")
        schemeHandler.unregister(host: mounted.artifact.originHost)
        self.mounted = nil
    }

    /// Tear the host down completely. After this the instance is unusable.
    func destroy() {
        boundHandler = Self.unboundHandler
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

    private func markReady() {
        guard !isReady else { return }
        isReady = true
        let waiting = readyContinuations
        readyContinuations.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
    }

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
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Only our own scheme may ever load. This is what stops a top-level
        // navigation from replacing the shell, and it is checked here as
        // well as in CSP because a navigation is not a subresource fetch.
        guard navigationAction.request.url?.scheme == SpiralAppScheme.scheme else {
            MXLog.info("[SpiralApp] cancelled navigation to a foreign scheme")
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Only the shell document makes the host ready; an iframe load does
        // not come through here as a main-frame finish.
        if webView.url?.host == SpiralAppScheme.shellHost {
            markReady()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        MXLog.error("[SpiralApp] shell navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: any Error) {
        MXLog.error("[SpiralApp] shell provisional navigation failed: \(error)")
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
