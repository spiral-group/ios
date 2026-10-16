//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 6): drives the runtime spike and
// collects its evidence.
//
// The spike answers one question — can hostile JavaScript reach the network
// or the previous app — and it must answer it with output, not reasoning.
// This type mounts the probe artifact in a real pooled host, reads the
// report the probe publishes, and produces text to paste into
// `~/Projects/docs/walkthroughs/0066-runtime-spike.md`.
//
// DEBUG only. A release build has no way to reach the probe: the shell
// package refuses to vend it and the scheme handler refuses to serve it.
//

#if DEBUG

import CryptoKit
import Foundation
import SpiralAppShell

@MainActor
final class SpiralAppSpikeRunner {
    struct CheckResult: Decodable {
        let name: String
        let verdict: String
        let detail: String
    }

    struct ProbeReport: Decodable {
        let startedAt: String
        let finishedAt: String
        let userAgent: String
        let network: [CheckResult]
        let escape: [CheckResult]
        let resource: [CheckResult]
        let leak: [CheckResult]
        let pass: Bool
    }

    enum SpikeError: LocalizedError {
        case probeMissing
        case digestFailed
        case noReport
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .probeMissing: "probe.jsx is not in the shell bundle (DEBUG build required)"
            case .digestFailed: "probe bytes did not match their own digest"
            case .noReport: "the probe never published a report — it may have failed to compile or mount"
            case .decodingFailed(let detail): "could not decode the probe report: \(detail)"
            }
        }
    }

    private var host: SpiralAppWebViewHost?

    /// Reports delivered over the port, newest last.
    ///
    /// The probe cannot be read out of the frame — its opaque origin makes it
    /// unreadable from the shell, which is the isolation being tested — so it
    /// posts its findings through `spike.report`, a method production mounts
    /// never grant.
    private var receivedReports: [ProbeReport] = []
    private var reportWaiters: [ReportWaiter] = []
    /// How many of ``receivedReports`` a caller has already taken, so a
    /// second `waitForReport()` does not hand back the first run's findings.
    private var consumedReports = 0

    /// Run the probe once in a freshly warmed host.
    func runOnce() async throws -> ProbeReport {
        let host = try makeHost()
        self.host = host
        let mount = try makeProbeMount(instanceID: "spike-run-1")
        try await host.mount(mount)
        return try await waitForReport()
    }

    /// Mount the probe, tear it down, and mount it again in the SAME host.
    ///
    /// This is spike item 9, the one that decides whether pooling is safe.
    /// The second report must show every `leak` check blocked; a marker from
    /// the first run surviving means destroying the iframe did not discard
    /// its realm, and the pool has to go.
    func runReuseCheck() async throws -> (first: ProbeReport, second: ProbeReport) {
        let host = try makeHost()
        self.host = host

        try await host.mount(makeProbeMount(instanceID: "spike-reuse-1"))
        let first = try await waitForReport()

        await host.unmount()

        // `unmount()` unbinds the bridge — that is the pool's guarantee that a
        // parked host cannot answer for the app it just served — so the second
        // app is bound afresh, exactly as the pool does before every mount.
        // A different digest would be a different origin, which would prove
        // nothing about reuse. The same artifact in the same host is the
        // hostile case: if anything survives, it survives between two apps
        // that the pool would happily run back to back.
        host.bind(bridgeHandler)
        try await host.mount(makeProbeMount(instanceID: "spike-reuse-2"))
        let second = try await waitForReport()

        return (first, second)
    }

    func tearDown() {
        host?.destroy()
        host = nil
    }

    // MARK: - Wiring

    private func makeHost() throws -> SpiralAppWebViewHost {
        SpiralAppWebViewHost(allowsSpikeProbe: true, methodHandler: bridgeHandler)
    }

    /// The spike is about isolation, not about the API surface, so the bridge
    /// answers the minimum that lets the probe's quota checks get replies,
    /// accepts the report, and refuses everything else. A real host routes
    /// these into Matrix. Named so a reuse check can bind it a second time.
    private var bridgeHandler: SpiralAppMethodHandler {
        { [weak self] method, args, _ in
            switch method {
            case SpiralAppCapability.appContextRead.rawValue:
                return SpiralAppBridge.success(["instanceId": "spike", "userId": "@spike:local"])

            case "spike.report":
                self?.ingestReport(args)
                return SpiralAppBridge.success(nil)

            default:
                return SpiralAppBridge.failure(code: "unavailable", message: "not implemented in the spike host")
            }
        }
    }

    private func ingestReport(_ args: Data) {
        do {
            let report = try JSONDecoder().decode(ProbeReport.self, from: args)
            receivedReports.append(report)
            let waiters = reportWaiters
            reportWaiters.removeAll()
            // `waitForReport` does the accounting when its continuation
            // resolves, so nothing is consumed here.
            for waiter in waiters {
                waiter.resume(report)
            }
        } catch {
            MXLog.error("[SpiralApp] could not decode a probe report: \(error)")
        }
    }

    private func makeProbeMount(instanceID: String) throws -> SpiralAppMount {
        guard let packed = SpiralAppShell.spikeProbeArtifact else {
            throw SpikeError.probeMissing
        }

        // Verified against the digest the packer wrote, not one recomputed
        // here: a probe whose bytes and digest disagree is exactly what the
        // verifier exists to refuse, and the spike should see that refusal.
        guard let artifact = SpiralAppArtifact.verified(packed: packed.bytes,
                                                        claimedDigest: packed.digest) else {
            throw SpikeError.digestFailed
        }

        // The four a real post gets, plus the channel the probe reports on.
        // Production would refuse this manifest, which is the point of the
        // probe asking for it.
        guard let capabilities = SpiralAppCapability.granted(requestedBy: artifact.manifest,
                                                             from: SpiralAppCapability.production + [.spikeReport]) else {
            throw SpikeError.digestFailed
        }

        return SpiralAppMount(instanceID: instanceID, artifact: artifact, capabilities: capabilities)
    }

    /// Wait for the next report to arrive over the port.
    ///
    /// A timeout is a finding, not a bug in the harness: it means the probe
    /// never compiled, never mounted, or could not reach the port — each of
    /// which the walkthrough must record rather than retry past.
    private func waitForReport(timeout: TimeInterval = 30) async throws -> ProbeReport {
        // A report may already have arrived while the caller was mounting.
        if receivedReports.count > consumedReports {
            let report = receivedReports[consumedReports]
            consumedReports += 1
            return report
        }

        let report: ProbeReport? = await withCheckedContinuation { continuation in
            let waiter = ReportWaiter(continuation)
            reportWaiters.append(waiter)

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.reportWaiters.removeAll { $0 === waiter }
                waiter.resume(nil)
            }
        }

        guard let report else { throw SpikeError.noReport }
        consumedReports += 1
        return report
    }

    /// Resolves exactly once, whether by a report arriving or by the timeout.
    @MainActor
    private final class ReportWaiter {
        private var continuation: CheckedContinuation<ProbeReport?, Never>?

        init(_ continuation: CheckedContinuation<ProbeReport?, Never>) {
            self.continuation = continuation
        }

        func resume(_ report: ProbeReport?) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(returning: report)
        }
    }

    // MARK: - Evidence

    /// Render a report as the markdown block that goes into the walkthrough.
    static func markdown(for report: ProbeReport, title: String) -> String {
        var lines: [String] = []
        lines.append("### \(title)")
        lines.append("")
        lines.append("- verdict: **\(report.pass ? "PASS" : "FAIL")**")
        lines.append("- started: `\(report.startedAt)` finished: `\(report.finishedAt)`")
        lines.append("- user agent: `\(report.userAgent)`")
        lines.append("")
        lines.append("| group | check | verdict | detail |")
        lines.append("|---|---|---|---|")

        let groups = [("network", report.network), ("escape", report.escape),
                      ("resource", report.resource), ("leak", report.leak)]
        for (group, results) in groups {
            for result in results {
                let detail = result.detail.replacingOccurrences(of: "|", with: "\\|")
                lines.append("| \(group) | `\(result.name)` | \(result.verdict) | \(detail) |")
            }
        }
        return lines.joined(separator: "\n")
    }
}

#endif
