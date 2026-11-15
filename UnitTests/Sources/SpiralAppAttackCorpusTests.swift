//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (security pass 2, step 2): the post-sandbox attack corpus,
// run in the real WKWebView host. Findings and the table:
// `docs/DESIGNS/post-sandbox-attack-corpus-2026-11-07.md`.
//
// Off unless asked for, because it needs the canary listener on the Mac and
// takes minutes:
//
//   python3 -I Tools/Scripts/spiral-post-canary.py <out> &
//   TEST_RUNNER_SPIRAL_CORPUS=1 TEST_RUNNER_SPIRAL_CORPUS_OUT=<out> \
//     Tools/Scripts/run-unit-tests.sh -only-testing:UnitTests/SpiralAppAttackCorpusTests
//
// `TEST_RUNNER_SPIRAL_CORPUS_ONLY=name,name` runs a subset. On a device the
// canary listens on the Mac's LAN address (`spiral-post-canary.py <out> <ip>`)
// and `TEST_RUNNER_SPIRAL_CORPUS_CANARY_HOST=<ip>` aims the attacks there; the
// run waits up to three minutes for the listener, long enough to answer the
// phone's Local Network prompt. Each ESCAPED
// attack is recorded as an issue, so a run with an open finding is red.
//

#if DEBUG

import Foundation
import Network
@testable import Spiral
import Testing
import WebKit

@MainActor
struct SpiralAppAttackCorpusTests {
    private nonisolated static let environment = ProcessInfo.processInfo.environment
    private nonisolated static let isEnabled = environment["SPIRAL_CORPUS"] != nil

    /// No heavy attack starts with the Mac's swap above this.
    private static let swapCeilingGigabytes = 13.0

    /// The writer, then readers that must not find what it planted.
    private static let leakGroup = ["spiral-leak-writer", "spiral-leak-reader-concurrent", "spiral-leak-reader-reuse",
                                    "spiral-leak-reader-account", "request-copy"]

    @Test(.enabled(if: isEnabled), .timeLimit(.minutes(60)))
    func theCorpusFindsNoWayOut() async throws {
        let runner = SpiralAppAttackRunner()
        defer { runner.tearDown() }

        // A device asks for Local Network access on the first connection.
        let listening = ContinuousClock.now + .seconds(180)
        while await Canary.stats() == nil, ContinuousClock.now < listening {
            try? await Task.sleep(for: .seconds(2))
        }
        let canaryWorks = await Self.positiveControls(runner)
        try #require(canaryWorks.listener, "the canary listener is not reachable on \(Canary.host):47914")

        let only = Self.environment["SPIRAL_CORPUS_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        // A real-tap attack waits for a person's taps, so it runs only when named.
        let corpus = SpiralAppAttackRunner.loadCorpus().filter { only?.contains($0.name) ?? !$0.checks.contains("real-tap") }
        try #require(!corpus.isEmpty, "no attacks in the test bundle")

        let isHeavy = { (attack: SpiralAppAttackRunner.Attack) in
            attack.threat == "resource" || attack.checks.contains("spin") || attack.checks.contains("liveness")
        }
        var outcomes: [SpiralAppAttackRunner.Outcome] = []

        for attack in corpus where !isHeavy(attack) && !Self.leakGroup.contains(attack.name) {
            if attack.checks.contains("production-refuses") {
                outcomes.append(Self.productionGrant(attack, runner: runner))
                continue
            }
            outcomes.append(await runner.run(attack))
        }

        outcomes += await Self.leakSequence(corpus, runner: runner)

        // A post that spins before it paints leaves its mount hanging (finding F3), so it goes last.
        for attack in corpus.filter(isHeavy).sorted(by: { ($0.name == "fallback-at-boot" ? 1 : 0) < ($1.name == "fallback-at-boot" ? 1 : 0) }) {
            // The simulator's processes are the Mac's: one run took swap to
            // 34 GB. Above the ceiling the rest are recorded as not run.
            if let swap = SpiralAppAttackRunner.swapUsedGigabytes(), swap > Self.swapCeilingGigabytes {
                var skipped = SpiralAppAttackRunner.Outcome(attack: attack.name, threat: attack.threat, expect: attack.expect,
                                                            checklist: attack.checklist, note: attack.note)
                skipped.verdict = "not run"
                skipped.why = [String(format: "the Mac's swap was at %.1f GB, above the %.0f GB ceiling", swap, Self.swapCeilingGigabytes)]
                outcomes.append(skipped)
                continue
            }
            outcomes.append(await Self.heavy(attack, runner: runner))
            await runner.write(outcomes, name: "corpus-results")
        }

        var controls = canaryWorks.outcome
        controls.why.append("listener reachable from the test process: \(canaryWorks.listener)")
        outcomes.insert(controls, at: 0)
        outcomes.insert(await Self.proxyControl(), at: 1)
        outcomes.insert(await Self.webRTCControl(), at: 2)
        if Canary.host != "127.0.0.1" { outcomes.insert(await Self.dnsControl(), at: 3) }
        await runner.write(outcomes, name: "corpus-results")

        for outcome in outcomes where outcome.verdict == "ESCAPED" {
            Issue.record("\(outcome.attack) ESCAPED: \(outcome.why.joined(separator: " | "))")
        }
        let tally = Dictionary(grouping: outcomes, by: \.verdict).mapValues(\.count)
        MXLog.info("[corpus] \(outcomes.count) run: \(tally)")
    }

    // MARK: - Groups

    /// A plain web view, no sandbox, no CSP: proves the canary can see a
    /// WebContent process on this simulator at all. Without it "no hits"
    /// would mean nothing.
    private static func positiveControls(_ runner: SpiralAppAttackRunner) async -> (listener: Bool, outcome: SpiralAppAttackRunner.Outcome) {
        var outcome = SpiralAppAttackRunner.Outcome(attack: "control-plain-webview", threat: "control", expect: "hits",
                                                    checklist: "—", note: "A plain WKWebView loading the canary: must hit.")
        guard let before = await Canary.stats() else { return (false, outcome) }
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        webView.loadHTMLString(Canary.aimed("""
        <img src="http://127.0.0.1:47913/c/control/img"><img src="https://127.0.0.1:47915/c/control/img-tls">
        <script>fetch("http://127.0.0.1:47913/c/control/fetch").catch(()=>{})</script>
        """), baseURL: URL(string: "http://\(Canary.host):47913/c/control/"))
        try? await Task.sleep(for: .seconds(4))
        let after = await Canary.stats()
        outcome.canaryHits = (after?.hits ?? []).dropFirst(before.total).map { "\($0.kind):\($0.port) \($0.line)" }
        outcome.verdict = outcome.canaryHits.isEmpty ? "CONTROL FAILED" : "control ok"
        return (true, outcome)
    }

    /// The host's dead proxy (F1) only helps if WebKit's `_blank` preconnect
    /// goes through the data store's proxy at all. A plain web view whose
    /// proxy IS the canary's counting port clicks one: the CONNECT must land
    /// there, not on the named host. A host on loopback is never proxied,
    /// which is why the link guard exists beside the proxy.
    private static func proxyControl() async -> SpiralAppAttackRunner.Outcome {
        var outcome = SpiralAppAttackRunner.Outcome(attack: "control-proxy-carries-preconnect", threat: "control", expect: "hits",
                                                    checklist: "—", note: "A _blank preconnect from a sandboxed frame, through a proxy on the canary.")
        let store = WKWebsiteDataStore.nonPersistent()
        var proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .init(Canary.host), port: 47915))
        proxy.allowFailover = false
        store.proxyConfigurations = [proxy]
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: configuration)
        let before = await Canary.stats()?.total ?? 0
        webView.loadHTMLString("""
        <iframe sandbox="allow-scripts" srcdoc="<script>var a=document.createElement('a');a.href='https://proxy-control.invalid/x';a.target='_blank';a.click();</script>"></iframe>
        """, baseURL: nil)
        try? await Task.sleep(for: .seconds(4))
        outcome.canaryHits = (await Canary.stats()?.hits ?? []).dropFirst(before).map { "\($0.kind):\($0.port) \($0.line)" }
        outcome.verdict = outcome.canaryHits.contains { $0.hasPrefix("tcp:47915") } ? "control ok" : "CONTROL FAILED"
        return outcome
    }

    /// WebRTC from a plain web view on this simulator: STUN must reach the
    /// canary's UDP port, or "no hit" from the WebRTC attacks means nothing.
    private static func webRTCControl() async -> SpiralAppAttackRunner.Outcome {
        var outcome = SpiralAppAttackRunner.Outcome(attack: "control-webrtc-plain-webview", threat: "control", expect: "hits",
                                                    checklist: "—", note: "A plain WKWebView's RTCPeerConnection with a STUN server on the canary.")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        let before = await Canary.stats()?.total ?? 0
        webView.loadHTMLString(Canary.aimed("""
        <script>(async function () {
          var pc = new RTCPeerConnection({ iceServers: [{ urls: "stun:127.0.0.1:47913" },
            { urls: "turn:127.0.0.1:47915?transport=tcp", username: "u", credential: "p" }] });
          pc.createDataChannel("x"); await pc.setLocalDescription(await pc.createOffer());
        })();</script>
        """), baseURL: URL(string: "http://localhost/"))
        try? await Task.sleep(for: .seconds(5))
        outcome.canaryHits = (await Canary.stats()?.hits ?? []).dropFirst(before).map { "\($0.kind):\($0.port) \($0.line)" }
        outcome.verdict = outcome.canaryHits.isEmpty ? "CONTROL FAILED" : "control ok"
        return outcome
    }

    /// Device pass only: a plain web view looking up a chosen name. Its
    /// witness is the packet capture: a DNS query for
    /// `spiral-dns-control.example.com` must show there, or "no query" for the
    /// attacks' `<label>.example.com` names means nothing (encrypted DNS, say).
    private static func dnsControl() async -> SpiralAppAttackRunner.Outcome {
        var outcome = SpiralAppAttackRunner.Outcome(attack: "control-dns-plain-webview", threat: "control", expect: "hits",
                                                    checklist: "—", note: "A plain WKWebView loading https://spiral-dns-control.example.com: the pcap must show the query.")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        await Canary.mark("start control-dns-plain-webview")
        // https: App Transport Security refuses a plain-http load of a host
        // name before any lookup, so an http control proves nothing.
        webView.loadHTMLString("""
        <img src="https://spiral-dns-control.example.com/c/control/dns">
        """, baseURL: nil)
        try? await Task.sleep(for: .seconds(4))
        await Canary.mark("end control-dns-plain-webview")
        outcome.verdict = "see pcap"
        outcome.why = ["the witness is a DNS query for spiral-dns-control.example.com in the packet capture"]
        return outcome
    }

    private static func productionGrant(_ attack: SpiralAppAttackRunner.Attack, runner: SpiralAppAttackRunner) -> SpiralAppAttackRunner.Outcome {
        var outcome = SpiralAppAttackRunner.Outcome(attack: attack.name, threat: attack.threat, expect: attack.expect,
                                                    checklist: attack.checklist, note: attack.note)
        let artifact = runner.pack(attack)
        let granted = artifact.flatMap { SpiralAppCapability.granted(requestedBy: $0.manifest, from: SpiralAppCapability.production) }
        outcome.verdict = granted == nil ? "held" : "ESCAPED"
        outcome.why = [granted == nil ? "production refused the whole mount" : "production granted \(granted ?? [])"]
        return outcome
    }

    private static func leakSequence(_ corpus: [SpiralAppAttackRunner.Attack], runner: SpiralAppAttackRunner) async -> [SpiralAppAttackRunner.Outcome] {
        let byName = Dictionary(uniqueKeysWithValues: corpus.map { ($0.name, $0) })
        guard let writer = byName["spiral-leak-writer"] else { return [] }
        var outcomes: [SpiralAppAttackRunner.Outcome] = []
        let writerPost = "$post-spiral-leak-writer"

        // The writer stays live while a second web view reads beside it.
        let writing = await runner.start(writer, postID: writerPost)
        try? await Task.sleep(for: .seconds(3))
        var concurrent: SpiralAppAttackRunner.Live?
        if let reader = byName["spiral-leak-reader-concurrent"] {
            concurrent = await runner.start(reader)
            if let concurrent { outcomes.append(await runner.finish(concurrent, attack: reader, keepHost: true)) }
        }
        outcomes.insert(await runner.finish(writing, attack: writer, keepHost: true), at: 0)
        // Released concurrent-first so the pool hands the WRITER's web view to the next post.
        if let concurrent { await runner.release(concurrent) }
        await runner.release(writing)

        if let reader = byName["spiral-leak-reader-reuse"] {
            outcomes.append(await runner.run(reader))
        }
        if let reader = byName["spiral-leak-reader-account"] {
            let other = await runner.makeRoom(postID: writerPost, account: SpiralAppAttackRunner.secondAccount)
            outcomes.append(await runner.run(reader, postID: writerPost, room: other))

            // Control: the same reader as the writer's own account on the writer's
            // post MUST find the private marker, or the readers above proved nothing.
            var control = await runner.run(reader, postID: writerPost)
            control.attack = "control-same-account-same-post"
            control.threat = "control"
            control.verdict = control.why.contains(where: { $0.contains("marker") }) ? "control ok" : "CONTROL FAILED"
            control.why.append("must find the writer's own private corner")
            outcomes.append(control)
        }
        if let copy = byName["request-copy"] {
            outcomes.append(await runner.run(copy))
        }
        return outcomes
    }

    /// Hangs, floods and allocations, each with a neighbouring post that must
    /// keep answering and a fresh post mounted afterwards.
    private static func heavy(_ attack: SpiralAppAttackRunner.Attack, runner: SpiralAppAttackRunner) async -> SpiralAppAttackRunner.Outcome {
        let neighbour = await runner.neighbour()
        let live = await runner.start(attack)
        try? await Task.sleep(for: .seconds(2))
        let neighbourAlive = await neighbour?.waitForPaint()
        var outcome = await runner.finish(live, attack: attack)
        outcome.neighbourAlive = neighbourAlive
        neighbour?.destroy()
        let (seconds, error) = await runner.recovery()
        outcome.recoveryMountSeconds = seconds
        outcome.recoveryError = error
        if error != nil { outcome.why.append("a fresh post could not mount afterwards: \(error ?? "")") }
        if neighbourAlive == false { outcome.why.append("a post in another web view stopped answering") }
        return outcome
    }
}

#endif
