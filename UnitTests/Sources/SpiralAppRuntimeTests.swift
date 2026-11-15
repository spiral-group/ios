//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007): exercises the Interactive Post
// runtime end to end in a simulator.
//
// This is NOT the spike and does not contribute to its gate. The simulator
// shares the Mac's network stack and process accounting, so neither "no
// network" nor "how many WebContent processes" means anything here — see
// `docs/walkthroughs/0066-runtime-spike.md` § "Why the simulator does not
// count".
//
// What it IS good for: proving the harness itself works before spending
// device time on it. If the shell never warms, the scheme handler never
// answers, or the probe never reports, that is a bug in our plumbing and it
// should fail here rather than on a phone.
//

#if DEBUG

import CryptoKit
import Foundation
@testable import Spiral
import SpiralAppShell
import SpiralAppTestArtifacts
import Testing
import UIKit
import WebKit

@MainActor
struct SpiralAppRuntimeTests {
    // MARK: - The host

    /// A shell that doesn't come is a host that has died, not a wait for ever.
    /// F1: every connection a post's web view opens goes to the dead proxy,
    /// with no fall back to a direct one, and the link guard, the WebRTC
    /// removal and the clipboard removal run in every frame. Dropping any of
    /// them fails here.
    @Test
    func aPostWebViewHasNoNetworkLinksOrWebRTC() throws {
        let host = SpiralAppWebViewHost()
        defer { host.destroy() }
        let webView = try #require(host.containerView.subviews.compactMap { $0 as? WKWebView }.first)

        let proxies = webView.configuration.websiteDataStore.proxyConfigurations
        #expect(proxies.count == 1)
        #expect(proxies.first?.allowFailover == false)

        // In every frame, before any page script: either alone would let a
        // post's frame, or its first line, run without them.
        let scripts = webView.configuration.userContentController.userScripts
        let guards = [scripts.first { $0.source.contains("lock(EventTarget.prototype, 'dispatchEvent'") },
                      scripts.first { $0.source.contains("RTCPeerConnection") && $0.source.contains("configurable: false") },
                      scripts.first { $0.source.contains("'clipboard'") && $0.source.contains("'execCommand'") }]
        for (name, script) in zip(["the link guard", "the WebRTC removal", "the clipboard removal"], guards) {
            let script = try #require(script, "\(name) is not injected")
            #expect(script.injectionTime == .atDocumentStart, "\(name)")
            #expect(script.isForMainFrameOnly == false, "\(name)")
        }
    }

    /// F11: a post wrote the pasteboard after a real tap. In the post's own
    /// frame the async Clipboard API is gone for good, `execCommand` refuses
    /// copy, cut and paste and still runs other commands, and a copy event's
    /// `clipboardData` is null. The frame reports to the shell's window.
    @Test(.timeLimit(.minutes(1)))
    func aPostFrameHasNoClipboard() async throws {
        let bytes = Self.packed(#"""
        const t = document.createElement("textarea");
        t.value = "x";
        document.body.appendChild(t);
        t.select();
        const tried = (fn) => { try { return fn(); } catch (error) { return "threw " + error.name; } };
        const clipboard = typeof navigator.clipboard;
        const restore = tried(() => {
          Object.defineProperty(Navigator.prototype, "clipboard", { get: () => "back", configurable: true });
          return String(navigator.clipboard);
        });
        parent.postMessage({ clipboardProbe: {
          clipboard,
          restored: restore,
          clipboardClass: typeof window.Clipboard,
          clipboardItem: typeof window.ClipboardItem,
          copy: tried(() => document.execCommand("copy")),
          cut: tried(() => document.execCommand("Cut")),
          paste: tried(() => document.execCommand(" paste ".trim())),
          copySupported: tried(() => document.queryCommandSupported("copy")),
          pastePlainSupported: tried(() => document.queryCommandSupported("PasteAsPlainText")),
          selectAll: tried(() => document.execCommand("selectAll")),
          execCommandLocked: Object.getOwnPropertyDescriptor(Document.prototype, "execCommand").configurable === false,
          clipboardData: String(new ClipboardEvent("copy", { clipboardData: new DataTransfer() }).clipboardData),
        } }, "*");
        export default () => null;
        """#)
        let artifact = try #require(SpiralAppArtifact.verified(packed: bytes, claimedDigest: Self.digest(of: bytes)))
        let host = SpiralAppWebViewHost()
        defer { host.destroy() }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false
        host.containerView.frame = window.bounds
        window.addSubview(host.containerView)
        try await host.waitUntilReady()
        _ = await SpiralAppAttackRunner.evaluate(host, """
        window.addEventListener('message', function (event) {
          if (event.data && event.data.clipboardProbe) window.__clipboardProbe = JSON.stringify(event.data.clipboardProbe);
        }); 'listening'
        """)

        try await host.mount(SpiralAppMount(instanceID: "clipboard", artifact: artifact, capabilities: [], viewerID: "@a:spiral.md"))

        var answer: String?
        let deadline = ContinuousClock.now + .seconds(10)
        while answer == nil, ContinuousClock.now < deadline {
            answer = await SpiralAppAttackRunner.evaluate(host, "window.__clipboardProbe || null")
            if answer == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        let json = try #require(answer, "the post's frame never reported")
        let facts = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], "\(json)")
        #expect(facts["clipboard"] as? String == "undefined", "\(json)")
        #expect((facts["restored"] as? String)?.hasPrefix("threw") == true, "the post put navigator.clipboard back: \(json)")
        #expect(facts["clipboardClass"] as? String == "undefined", "\(json)")
        #expect(facts["clipboardItem"] as? String == "undefined", "\(json)")
        for command in ["copy", "cut", "paste", "copySupported", "pastePlainSupported"] {
            #expect(facts[command] as? Bool == false, "\(command): \(json)")
        }
        #expect(facts["selectAll"] as? Bool == true, "other commands must still run: \(json)")
        #expect(facts["execCommandLocked"] as? Bool == true, "\(json)")
        #expect(facts["clipboardData"] as? String == "null", "\(json)")
    }

    @Test
    func theWaitForAShellIsBounded() async {
        let host = SpiralAppWebViewHost(readyDeadline: .milliseconds(1))
        var didDie = false
        host.onContentProcessDied = { didDie = true }

        await #expect(throws: SpiralAppHostError.self) {
            try await host.waitUntilReady()
        }

        #expect(didDie)
        host.destroy()
    }

    /// A mount waits for its view to reach a window. A host given back
    /// meanwhile may already be the next post's, so the mount doesn't go on.
    @Test
    func aMountGivenBackWhileItWaitsNeverStarts() async throws {
        let bytes = Self.packed("export default () => null;")
        let artifact = try #require(SpiralAppArtifact.verified(packed: bytes, claimedDigest: Self.digest(of: bytes)))
        let host = SpiralAppWebViewHost()
        try await host.waitUntilReady()

        let mounting = Task {
            try await host.mount(SpiralAppMount(instanceID: "left", artifact: artifact, capabilities: [], viewerID: "@a:spiral.md"))
        }
        try await Task.sleep(for: .milliseconds(100))
        await host.unmount()

        await #expect(throws: SpiralAppHostError.unmountedWhileWaiting) {
            try await mounting.value
        }
        host.destroy()
    }

    /// A prewarmed host waits with no window. If WebKit suspended a page that
    /// has none, its shell wouldn't load until a row took it, and the overlap
    /// would be for nothing.
    @Test
    func aShellLoadsWithNoWindow() async throws {
        let parked = SpiralAppWebViewHost()
        let parkedStart = ContinuousClock.now
        try await parked.waitUntilReady()
        let parkedTime = parkedStart.duration(to: .now)

        let shown = SpiralAppWebViewHost()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false
        shown.containerView.frame = window.bounds
        window.addSubview(shown.containerView)
        let shownStart = ContinuousClock.now
        try await shown.waitUntilReady()
        let shownTime = shownStart.duration(to: .now)

        let again = SpiralAppWebViewHost()
        let againStart = ContinuousClock.now
        try await again.waitUntilReady()
        let againTime = againStart.duration(to: .now)

        MXLog.info("[experiment] shell ready: no window \(parkedTime), in a window \(shownTime), no window again \(againTime)")
        parked.destroy()
        shown.destroy()
        again.destroy()
    }

    /// The fake host answers `waitForPaint` by itself. A real page that didn't
    /// answer in time would cost a healthy app its host, so this is the row
    /// leaving and coming back with real WebKit: a picture on the way out, and
    /// a page that draws on the way in.
    @Test
    func aRealAppLeavesAPictureAndDrawsWhenItComesBack() async throws {
        let bytes = Self.packed("export default () => 'still here';")
        let artifact = try #require(SpiralAppArtifact.verified(packed: bytes, claimedDigest: Self.digest(of: bytes)))
        let host = SpiralAppWebViewHost()
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        let parent = UIViewController()
        window.rootViewController = parent
        window.makeKeyAndVisible()
        host.containerView.frame = window.bounds
        parent.view.addSubview(host.containerView)
        try await host.mount(SpiralAppMount(instanceID: "away", artifact: artifact, capabilities: [], viewerID: "@a:spiral.md"))

        var picture: UIImage?
        var hasAnswered = false
        host.takeSnapshot { image in
            picture = image
            hasAnswered = true
        }
        host.containerView.removeFromSuperview()
        let deadline = ContinuousClock.now + .seconds(2)
        while !hasAnswered, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(picture != nil, "no picture of a real app")

        try await Task.sleep(for: .seconds(1))
        parent.view.addSubview(host.containerView)
        let start = ContinuousClock.now
        let hasDrawn = await host.waitForPaint()
        MXLog.info("[experiment] a page back in a window drew after \(start.duration(to: .now))")

        #expect(hasDrawn, "a healthy app was taken for a silent one")
        host.destroy()
        window.isHidden = true
    }

    /// Of WebKit, in an opaque-origin frame on our scheme, not of the document:
    /// this artifact imports nothing, so only a preload asks for the SDK and
    /// the kit, and a preload that the import didn't reuse fetches React twice.
    @Test
    func aFramePreloadsTheRuntimeAndFetchesItOnce() async throws {
        let bytes = Self.packed("export default () => null;")
        let artifact = try #require(SpiralAppArtifact.verified(packed: bytes, claimedDigest: Self.digest(of: bytes)))
        let host = SpiralAppWebViewHost()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false
        host.containerView.frame = window.bounds
        window.addSubview(host.containerView)
        SpiralAppSchemeHandler.requestedPathsForTesting = []

        try await host.mount(SpiralAppMount(instanceID: "preload", artifact: artifact, capabilities: [], viewerID: "@a:spiral.md"))

        let requested = SpiralAppSchemeHandler.requestedPathsForTesting
        // The same files for a second app in the same process: nothing new
        // comes off the disk.
        let readsBefore = SpiralAppSchemeHandler.diskReadsForTesting
        let second = Self.packed("export default () => 1 && null;")
        let secondArtifact = try #require(SpiralAppArtifact.verified(packed: second, claimedDigest: Self.digest(of: second)))
        try await host.mount(SpiralAppMount(instanceID: "again", artifact: secondArtifact, capabilities: [], viewerID: "@a:spiral.md"))
        #expect(SpiralAppSchemeHandler.diskReadsForTesting == readsBefore, "a bundled file was read from disk again")
        host.destroy()
        #expect(requested.contains("/runtime/v1/sdk.js"), "the preload never happened: \(requested)")
        #expect(requested.contains("/runtime/v1/ui.js"))
        #expect(requested.count { $0 == "/runtime/v1/react.js" } == 1, "React was fetched again: \(requested)")
        #expect(requested.count { $0 == "/runtime/v1/bootstrap.js" } == 1, "the bootstrap was fetched again: \(requested)")
    }

    /// A compiled module (a catalogue template, question 374) runs without
    /// the compiler; a source loads it, once, and runs too. A mount returns
    /// once the app has drawn, and throws on one that failed to compile.
    @Test
    func onlyASourceLoadsTheCompiler() async throws {
        let compiled = Self.packed(#"import { jsx as _jsx } from "react/jsx-runtime"; export default () => _jsx("p", { children: "compiled" });"#,
                                   entry: "app.js")
        let source = Self.packed("export default () => <p>source</p>;")
        let compiledArtifact = try #require(SpiralAppArtifact.verified(packed: compiled, claimedDigest: Self.digest(of: compiled)))
        let sourceArtifact = try #require(SpiralAppArtifact.verified(packed: source, claimedDigest: Self.digest(of: source)))
        #expect(compiledArtifact.manifest.isCompiled)
        #expect(!sourceArtifact.manifest.isCompiled)
        let host = SpiralAppWebViewHost()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.isHidden = false
        host.containerView.frame = window.bounds
        window.addSubview(host.containerView)

        SpiralAppSchemeHandler.requestedPathsForTesting = []
        try await host.mount(SpiralAppMount(instanceID: "compiled", artifact: compiledArtifact, capabilities: [], viewerID: "@a:spiral.md"))
        #expect(!SpiralAppSchemeHandler.requestedPathsForTesting.contains("/runtime/v1/compile.js"),
                "a compiled module loaded the compiler: \(SpiralAppSchemeHandler.requestedPathsForTesting)")

        SpiralAppSchemeHandler.requestedPathsForTesting = []
        try await host.mount(SpiralAppMount(instanceID: "source", artifact: sourceArtifact, capabilities: [], viewerID: "@a:spiral.md"))
        #expect(SpiralAppSchemeHandler.requestedPathsForTesting.count { $0 == "/runtime/v1/compile.js" } == 1,
                "\(SpiralAppSchemeHandler.requestedPathsForTesting)")
        host.destroy()
    }

    // MARK: - Artifact identity

    /// A packed container, built the way the TypeScript packer builds one.
    ///
    /// `SpiralAppContainerTests` checks this layout against the REAL shipped
    /// bytes; here it is only a fixture so these tests are about identity
    /// rather than about the format.
    private static func packed(_ source: String, entry: String = "app.jsx") -> Data {
        let manifest = #"{"app_id":"t","runtime":"1","entry":"\#(entry)","capabilities":[]}"#
        var bytes = Data("SPIRALv1\n".utf8)
        bytes.append(Data("manifest.json\n\(manifest.utf8.count)\n".utf8))
        bytes.append(Data(manifest.utf8))
        bytes.append(Data("\(entry)\n\(source.utf8.count)\n".utf8))
        bytes.append(Data(source.utf8))
        return bytes
    }

    private static func digest(of bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    @Test
    func verifiedArtifactAcceptsMatchingDigest() {
        let bytes = Self.packed("export default () => null;")
        let digest = Self.digest(of: bytes)

        let artifact = SpiralAppArtifact.verified(packed: bytes, claimedDigest: digest)

        #expect(artifact != nil)
        #expect(artifact?.digest == digest)
    }

    @Test
    func verifiedArtifactRejectsMismatchedDigest() {
        let bytes = Self.packed("export default () => null;")

        // A media repository that served different bytes than the event
        // claimed would look exactly like this.
        let artifact = SpiralAppArtifact.verified(packed: bytes,
                                                  claimedDigest: String(repeating: "0", count: 64))

        #expect(artifact == nil)
    }

    @Test
    func theDigestCoversTheManifestAndNotOnlyTheCode() {
        // Hashing the module alone would let a manifest be swapped for one
        // asking for different capabilities while the digest still matched.
        let source = "export default () => null;"
        let honest = Self.packed(source)

        var tampered = Data("SPIRALv1\n".utf8)
        let other = #"{"app_id":"t","runtime":"1","entry":"app.jsx","capabilities":["chat.message.send"]}"#
        tampered.append(Data("manifest.json\n\(other.utf8.count)\n".utf8))
        tampered.append(Data(other.utf8))
        tampered.append(Data("app.jsx\n\(source.utf8.count)\n".utf8))
        tampered.append(Data(source.utf8))

        #expect(Self.digest(of: honest) != Self.digest(of: tampered))
        #expect(SpiralAppArtifact.verified(packed: tampered, claimedDigest: Self.digest(of: honest)) == nil)
    }

    @Test
    func artifactOriginIsDerivedFromTheDigest() {
        let bytes = Self.packed("export default () => null;")
        let digest = Self.digest(of: bytes)
        let artifact = SpiralAppArtifact.verified(packed: bytes, claimedDigest: digest)

        // Two different artifacts must never share an origin, or a future
        // change that granted `allow-same-origin` would let them see each
        // other.
        #expect(artifact?.originHost == "a-\(digest)")
        #expect(artifact?.originHost != SpiralAppScheme.shellHost)
    }

    // MARK: - Shipped resources

    @Test
    func shellBundleCarriesTheRuntime() {
        // A missing resource here means `pnpm build:ios` was not run, and
        // every runtime test below would fail for an unrelated reason.
        #expect(SpiralAppShell.shellDocumentURL != nil)
        #expect(SpiralAppShell.runtimeBootstrapURL != nil)
        #expect(SpiralAppShell.runtimeReactURL != nil)
    }

    @Test
    func bundledResourceLookupRefusesUnknownPaths() {
        #expect(SpiralAppShell.bundledResource(forPath: "/runtime/v1/react.js") != nil)
        #expect(SpiralAppShell.bundledResource(forPath: "/etc/passwd") == nil)
        #expect(SpiralAppShell.bundledResource(forPath: "/../../secrets") == nil)
        #expect(SpiralAppShell.bundledResource(forPath: "/app.jsx") == nil)
    }

    @Test
    func theAppBundleCarriesNoTestArtifact() {
        // App Review F2 (decision 252): the probe is an adversary and the
        // others are scaffolding; only test targets link their product.
        #expect(SpiralAppShell.bundle.url(forResource: "artifacts", withExtension: nil, subdirectory: "dist") == nil)
        // The test bundle itself is injected under the app's PlugIns, so it is left out.
        let appFiles = (FileManager.default.enumerator(at: Bundle.main.bundleURL, includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.path(percentEncoded: false) } ?? [])
            .filter { !$0.contains(".xctest/") }
        #expect(appFiles.contains { $0.hasSuffix("/shell.html") }, "The host app's bundle should be the one listed.")
        #expect(!appFiles.contains { $0.hasSuffix(".spiralapp") })
        #expect(SpiralAppTestArtifacts.probe != nil)
    }

    // MARK: - End-to-end

    /// The whole pipeline: warm the shell, mount the hostile probe, and wait
    /// for the report it posts back over the port.
    ///
    /// Reaching a report at all proves a great deal of plumbing: the scheme
    /// handler answered, the synthesised document loaded, the bootstrap
    /// hardened and took the port, sucrase compiled a 17 kB artifact, the
    /// specifier rewrite resolved React to the shipped runtime, the blob
    /// import evaluated, React mounted, and the `spike.report` round trip
    /// worked through the shell's validation and quota checks.
    @Test(.timeLimit(.minutes(2)))
    func probeRunsAndReportsThroughThePort() async throws {
        let runner = SpiralAppSpikeRunner()
        defer { runner.tearDown() }

        let report = try await runner.runOnce()

        #expect(!report.network.isEmpty)
        #expect(!report.escape.isEmpty)
        #expect(!report.leak.isEmpty)

        // Simulator caveat: these verdicts are about our plumbing, not about
        // the gate. The checks that must hold REGARDLESS of platform are the
        // structural ones — the app cannot see the shell or the bridge,
        // because that follows from the sandbox attribute rather than from
        // the network stack.
        // Print everything that is not blocked, so a failure names the
        // finding instead of leaving it to be dug out of the device log.
        let notBlocked = (report.network + report.escape + report.leak)
            .filter { $0.verdict != "blocked" }
        for result in notBlocked {
            Issue.record("\(result.name): \(result.verdict) — \(result.detail)")
        }

        let escapeByName = Dictionary(uniqueKeysWithValues: report.escape.map { ($0.name, $0.verdict) })
        #expect(escapeByName["webkit-handlers"] == "blocked")
        #expect(escapeByName["shell-global"] == "blocked")
        #expect(escapeByName["parent-document"] == "blocked")
    }

    /// Spike item 9, run where it is cheap to run often.
    ///
    /// The device run is what counts, but a regression that let state leak
    /// between two apps in a reused web view would show up here too, and
    /// catching it in CI is worth far more than catching it on a phone.
    @Test(.timeLimit(.minutes(3)))
    func nothingSurvivesBetweenTwoAppsInAReusedWebView() async throws {
        let runner = SpiralAppSpikeRunner()
        defer { runner.tearDown() }

        let (first, second) = try await runner.runReuseCheck()

        #expect(first.leak.allSatisfy { $0.verdict == "blocked" })

        // The second mount is the real question: it runs in the same web
        // view the first one just used.
        let leaked = second.leak.filter { $0.verdict == "REACHED" }
        #expect(leaked.isEmpty, "state survived iframe teardown: \(leaked.map(\.name))")
    }
}

#endif
