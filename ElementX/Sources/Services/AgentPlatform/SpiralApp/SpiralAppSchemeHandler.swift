//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.3): the only source of bytes for
// an Interactive Post's web view.
//
// Everything the WebView can load comes through here, and the default is
// refusal. That is the whole point: with a custom scheme, WebKit cannot
// reach the network on its own behalf for these origins, so "no network" is
// a property of what we choose to answer rather than a policy we hope holds.
//
// Two origins, deliberately different:
//
//   spiral-app://shell/…      the TRUSTED document. A real file, because it
//                             is ours.
//   spiral-app://a-<digest>/… one untrusted artifact. Its `index.html` is
//                             SYNTHESISED here — never read from the
//                             artifact — so a generated app can never
//                             control its own <head>, its CSP, or what
//                             scripts the document loads.
//

import Foundation
import SpiralAppShell
import WebKit

/// Serves `spiral-app://` for one web view.
///
/// Registered per `WKWebViewConfiguration`. The registry of artifacts is
/// mutable because a pooled web view serves one app after another; the
/// handler holds no per-app state beyond it.
final class SpiralAppSchemeHandler: NSObject, WKURLSchemeHandler {
    /// Artifacts this handler may serve, keyed by origin host.
    ///
    /// Registering is what makes an artifact reachable at all. An unknown
    /// host is refused, so a frame cannot ask for an artifact that was never
    /// approved for it.
    private var artifactsByHost: [String: SpiralAppArtifact] = [:]

    /// The bundle's files, read once per process: they can't change, and each
    /// was read from disk on the main thread for every frame of every post.
    private static var bundledFiles: [URL: Data] = [:]

    #if DEBUG
    /// What frames have asked for, so a test can see what WebKit really did.
    static var requestedPathsForTesting: [String] = []
    /// How often a bundled file came off the disk.
    static var diskReadsForTesting = 0
    #endif

    /// Whether the Brief 0066 probe may be served. Debug builds only; a
    /// release build must never hand an adversary to a user.
    private let allowsSpikeProbe: Bool

    init(allowsSpikeProbe: Bool = false) {
        #if DEBUG
        self.allowsSpikeProbe = allowsSpikeProbe
        #else
        self.allowsSpikeProbe = false
        #endif
        super.init()
    }

    func register(_ artifact: SpiralAppArtifact) {
        artifactsByHost[artifact.originHost] = artifact
    }

    /// Whether `host` is an artifact this handler serves right now.
    func isServing(host: String) -> Bool {
        artifactsByHost[host] != nil
    }

    func unregister(host: String) {
        artifactsByHost.removeValue(forKey: host)
    }

    func unregisterAll() {
        artifactsByHost.removeAll()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let host = url.host else {
            fail(urlSchemeTask, reason: "malformed URL")
            return
        }

        let path = url.path.isEmpty ? "/" : url.path

        // Every byte the web view gets is one of these. Tracing them is how
        // a blank frame is told apart from a refused subresource — the
        // sandboxed frame is opaque, so this log is often the only view in.
        MXLog.verbose("[SpiralApp] request \(host)\(path)")
        #if DEBUG
        Self.requestedPathsForTesting.append(path)
        #endif

        switch host {
        case SpiralAppScheme.shellHost:
            serveShell(path: path, task: urlSchemeTask, url: url)
        default:
            guard let artifact = artifactsByHost[host] else {
                fail(urlSchemeTask, reason: "unknown artifact origin: \(host)")
                return
            }
            serveArtifact(artifact, path: path, task: urlSchemeTask, url: url)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Nothing to cancel: every response is produced synchronously from
        // memory or the app bundle.
    }

    // MARK: - Shell origin

    private func serveShell(path: String, task: any WKURLSchemeTask, url: URL) {
        switch path {
        case "/", "/index.html":
            guard let file = SpiralAppShell.shellDocumentURL,
                  let data = Self.contents(of: file) else {
                fail(task, reason: "shell document missing from the bundle")
                return
            }
            // The shell is ours, but it still gets a policy: it must not be
            // able to reach the network either, and it has no reason to.
            respond(task, url: url, data: data, mime: "text/html", extraHeaders: [
                "Content-Security-Policy": Self.shellPolicy(origin: Self.origin(for: SpiralAppScheme.shellHost))
            ])

        case "/shell.js":
            serveBundled(path: "/shell/shell.js",
                         task: task,
                         url: url,
                         mime: "text/javascript",
                         origin: Self.origin(for: SpiralAppScheme.shellHost))

        default:
            // Vite emits a source map reference; refusing it is harmless and
            // keeps the default closed.
            fail(task, reason: "not published on the shell origin: \(path)")
        }
    }

    // MARK: - Artifact origin

    private func serveArtifact(_ artifact: SpiralAppArtifact, path: String, task: any WKURLSchemeTask, url: URL) {
        switch path {
        case "/", "/index.html":
            let html = Self.synthesisedDocument(for: artifact)
            respond(task, url: url, data: Data(html.utf8), mime: "text/html", extraHeaders: [
                "Content-Security-Policy": Self.artifactPolicy(origin: Self.origin(for: artifact.originHost))
            ])

        case "/app.jsx":
            // The bytes were verified when the artifact was constructed
            // (`SpiralAppArtifact.verified`), so anything registered here has
            // already matched its digest.
            respond(task, url: url, data: artifact.source, mime: "text/plain", extraHeaders: [
                "Content-Security-Policy": Self.artifactPolicy(origin: Self.origin(for: artifact.originHost))
            ])

        case "/runtime/v1/bootstrap.js", "/runtime/v1/react.js", "/runtime/v1/sdk.js",
             "/runtime/v1/ui.js", "/runtime/v1/play.js", "/runtime/v1/compile.js":
            serveBundled(path: path,
                         task: task,
                         url: url,
                         mime: "text/javascript",
                         origin: Self.origin(for: artifact.originHost))

        case "/runtime/v1/ui.css":
            serveBundled(path: path,
                         task: task,
                         url: url,
                         mime: "text/css",
                         origin: Self.origin(for: artifact.originHost))

        default:
            fail(task, reason: "not published on an artifact origin: \(path)")
        }
    }

    private func serveBundled(path: String,
                              task: any WKURLSchemeTask,
                              url: URL,
                              mime: String,
                              origin: String) {
        guard let file = SpiralAppShell.bundledResource(forPath: path),
              let data = Self.contents(of: file) else {
            fail(task, reason: "bundled resource missing: \(path)")
            return
        }
        respond(task, url: url, data: data, mime: mime, extraHeaders: [
            "Content-Security-Policy": Self.artifactPolicy(origin: origin)
        ])
    }

    private static func contents(of file: URL) -> Data? {
        if let data = bundledFiles[file] {
            return data
        }
        #if DEBUG
        diskReadsForTesting += 1
        #endif
        let data = try? Data(contentsOf: file)
        bundledFiles[file] = data
        return data
    }

    // MARK: - Documents and policy

    /// The document an artifact runs in.
    ///
    /// Synthesised rather than read from the artifact so the app cannot
    /// choose its own policy, inject a script tag, or add an import map. The
    /// only script it loads is our bootstrap.
    ///
    /// `#root` scrolls ONLY in the full-screen viewer. In a row it did
    /// (`overflow:auto`), and a swipe that began on a post scrolled the post's
    /// insides instead of the timeline — on a row with a tall app the
    /// timeline was unreachable from most of the screen (2026-09-17). The
    /// bootstrap marks the document from the host's `viewport.changed`.
    ///
    /// The preloads turn a waterfall into one fetch: an import is only found
    /// once the module before it has run, and React waits on the bootstrap, the
    /// SDK on the compiled app. They name our own runtime and nothing else, and
    /// `script-src` governs them as it does the imports they stand in for.
    /// The compiler is not among them: only a module that arrives as source
    /// loads it (question 374). `data-compiled` is a fixed word, never text
    /// from the manifest, and only spares the compiler — the bootstrap
    /// checks a compiled module's imports as it checks a compiled source's.
    private static func synthesisedDocument(for artifact: SpiralAppArtifact) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
        <meta name="color-scheme" content="light dark">
        <title>Spiral app</title>
        <link rel="modulepreload" href="/runtime/v1/bootstrap.js">
        <link rel="modulepreload" href="/runtime/v1/react.js">
        <link rel="modulepreload" href="/runtime/v1/sdk.js">
        <link rel="modulepreload" href="/runtime/v1/ui.js">
        <link rel="stylesheet" href="/runtime/v1/ui.css">
        <style>
          html,body{margin:0;padding:0;height:100%;background:transparent;overflow:hidden;
            font:14px/1.4 -apple-system,system-ui,sans-serif;-webkit-text-size-adjust:100%}
          #root{position:absolute;inset:0;overflow:hidden}
          html[data-spiral-viewport=expanded] #root{overflow:auto;-webkit-overflow-scrolling:touch}
        </style>
        </head>
        <body>
        <div id="root"></div>
        <script type="application/json" id="spiral-artifact-source"\(artifact.manifest.isCompiled ? " data-compiled" : "")>\(embeddedSource(artifact.source))</script>
        <script type="module" src="/runtime/v1/bootstrap.js"></script>
        </body>
        </html>
        """
    }

    /// The artifact's source, embedded in its own document.
    ///
    /// The bootstrap used to `fetch("./app.jsx")`, which `connect-src 'none'`
    /// correctly refused — the policy cannot tell "my own source" from "a
    /// beacon". Relaxing `connect-src` to the artifact's origin would have
    /// worked, but `connect-src 'none'` with **no exceptions** is a far
    /// easier claim to verify, so the source travels in the document instead
    /// and the strongest line in the policy stays absolute.
    ///
    /// JSON-encoded, then `<` is escaped so no byte sequence in generated
    /// code can close the script element early.
    private static func embeddedSource(_ source: Data) -> String {
        let text = String(decoding: source, as: UTF8.self)
        guard let encoded = try? JSONSerialization.data(withJSONObject: [text]),
              let array = String(data: encoded, encoding: .utf8) else {
            return "\"\""
        }
        // `JSONSerialization` cannot encode a bare string, so it went through
        // a one-element array; drop the brackets.
        let json = String(array.dropFirst().dropLast())
        return json.replacingOccurrences(of: "<", with: "\\u003c")
    }

    /// Policy for an untrusted artifact.
    ///
    /// `connect-src 'none'` is the load-bearing line: it stops fetch, XHR,
    /// WebSocket, EventSource and sendBeacon below the JavaScript layer, so
    /// hostile code cannot argue its way past it. `frame-src 'none'` matters
    /// almost as much — a nested frame would be a fresh realm where the
    /// bootstrap's WebRTC hardening never ran.
    ///
    /// `blob:` in `script-src` is required by the zero-build design (the
    /// bootstrap compiles the artifact and imports it as a blob). It grants
    /// nothing to an attacker who is already running scripts: the network is
    /// governed by `connect-src`, not by `script-src`. Spike item 6 verifies
    /// that empirically rather than on this reasoning alone.
    /// Full origin of a host on our scheme, e.g. `spiral-app://a-9f2c…`.
    ///
    /// Policies name this explicitly instead of relying on `'self'`.
    /// `'self'` is defined against the protected resource's origin, and
    /// WebKit does not resolve it the way one would hope for a **custom**
    /// scheme: with `script-src 'self'` the shell's own `shell.js` was
    /// refused and `window.__spiralShell` never appeared. Naming the origin
    /// is both explicit and narrower than the obvious workaround of
    /// allowlisting the bare `spiral-app:` scheme, which would have let one
    /// artifact's document load another artifact's code.
    private static func origin(for host: String) -> String {
        "\(SpiralAppScheme.scheme)://\(host)"
    }

    private static func artifactPolicy(origin: String) -> String {
        [
            "default-src 'none'",
            "script-src \(origin) blob:",
            "style-src \(origin) 'unsafe-inline'",
            "img-src \(origin) data: blob:",
            "font-src \(origin)",
            "media-src \(origin) blob:",
            "connect-src 'none'",
            "frame-src 'none'",
            "child-src 'none'",
            "worker-src 'none'",
            "object-src 'none'",
            "base-uri 'none'",
            "form-action 'none'",
            "frame-ancestors \(self.origin(for: SpiralAppScheme.shellHost))"
        ].joined(separator: "; ")
    }

    /// The shell is trusted code, but it has no reason to reach the network
    /// either, so it gets the same denial with room for the frame it hosts.
    private static func shellPolicy(origin: String) -> String {
        [
            "default-src 'none'",
            "script-src \(origin)",
            "style-src \(origin) 'unsafe-inline'",
            "connect-src 'none'",
            // The shell must be able to frame an artifact, and artifact
            // origins are per-digest, so this one cannot name a single host.
            "frame-src \(SpiralAppScheme.scheme):",
            "object-src 'none'",
            "base-uri 'none'",
            "form-action 'none'"
        ].joined(separator: "; ")
    }

    // MARK: - Responses

    private func respond(_ task: any WKURLSchemeTask,
                         url: URL,
                         data: Data,
                         mime: String,
                         extraHeaders: [String: String]) {
        var headers = extraHeaders
        headers["Content-Type"] = mime
        headers["Content-Length"] = String(data.count)
        // Nothing here is cacheable across mounts: artifacts are addressed by
        // digest, so a changed app is a different URL anyway.
        headers["Cache-Control"] = "no-store"
        headers["Access-Control-Allow-Origin"] = "*"

        guard let response = HTTPURLResponse(url: url,
                                             statusCode: 200,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: headers) else {
            fail(task, reason: "could not build a response")
            return
        }

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// Refuse a request.
    ///
    /// Logged at info rather than error: a probe deliberately asks for
    /// things it should not get, and in production a refusal is the system
    /// working. A flood of these in a real room would show up as a broken
    /// app, not as a silent failure.
    private func fail(_ task: any WKURLSchemeTask, reason: String) {
        MXLog.info("[SpiralApp] refused: \(reason)")
        task.didFailWithError(NSError(domain: "SpiralAppSchemeHandler",
                                      code: NSURLErrorResourceUnavailable,
                                      userInfo: [NSLocalizedDescriptionKey: reason]))
    }
}
