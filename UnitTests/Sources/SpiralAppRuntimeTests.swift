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
@testable import ElementX
import Foundation
import SpiralAppShell
import Testing

@MainActor
struct SpiralAppRuntimeTests {
    // MARK: - Artifact identity

    /// A packed container, built the way the TypeScript packer builds one.
    ///
    /// `SpiralAppContainerTests` checks this layout against the REAL shipped
    /// bytes; here it is only a fixture so these tests are about identity
    /// rather than about the format.
    private static func packed(_ source: String) -> Data {
        let manifest = #"{"app_id":"t","runtime":"1","entry":"app.jsx","capabilities":[]}"#
        var bytes = Data("SPIRALv1\n".utf8)
        bytes.append(Data("manifest.json\n\(manifest.utf8.count)\n".utf8))
        bytes.append(Data(manifest.utf8))
        bytes.append(Data("app.jsx\n\(source.utf8.count)\n".utf8))
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
    func probeArtifactIsAvailableInDebugOnly() {
        // The probe is an adversary; a release build must not be able to
        // serve it. `spikeProbeArtifact` is `#if DEBUG` in the package.
        #expect(SpiralAppShell.spikeProbeArtifact != nil)
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
