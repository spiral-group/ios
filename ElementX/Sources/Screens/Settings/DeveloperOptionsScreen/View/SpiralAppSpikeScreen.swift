//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 6): the runtime spike harness.
//
// Not a product screen and not built to MVVM-C — it is the instrument that
// decides whether Interactive Posts ship at all, and it is deleted once the
// walkthrough is signed off. It runs the hostile probe against the real
// runtime, shows what got through, and produces the markdown that goes into
// `~/Projects/docs/walkthroughs/0066-runtime-spike.md`.
//
// Read the verdicts literally. A single `REACHED` in `network` or `escape`,
// or any `REACHED` in `leak`, fails the gate — there is no "mostly blocked".
//

#if DEBUG

import Compound
import CryptoKit
import SpiralAppShell
import SwiftUI

struct SpiralAppSpikeScreen: View {
    @State private var runner = SpiralAppSpikeRunner()
    @State private var status: Status = .idle
    @State private var reports: [(title: String, report: SpiralAppSpikeRunner.ProbeReport)] = []
    @State private var failure: String?
    @State private var liveHostCount = 0

    private enum Status: Equatable {
        case idle
        case running(String)
        case done
    }

    var body: some View {
        Form {
            securitySection
            performanceSection
            resultsSection
            evidenceSection
        }
        .compoundList()
        .navigationTitle("Spiral App spike")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            runner.tearDown()
            liveHostCount = 0
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        Section {
            ListRow(label: .default(title: "Run the probe once",
                                    description: "Mounts the hostile artifact and collects its report",
                                    icon: \.lock),
                    kind: .button { Task { await runOnce() } })

            ListRow(label: .default(title: "Reuse check (item 9)",
                                    description: "Mount, tear down, mount again in the SAME web view. The second run must find nothing from the first.",
                                    icon: \.restart),
                    kind: .button { Task { await runReuse() } })
        } header: {
            Text("Security")
                .compoundListSectionHeader()
        } footer: {
            Text(statusText)
                .compoundListSectionFooter()
        }
    }

    private var statusText: String {
        switch status {
        case .idle: "Nothing has run yet."
        case .running(let what): "Running: \(what)…"
        case .done: failure ?? "Finished. Read the verdicts below."
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        Section {
            Stepper("Live hosts: \(liveHostCount)", value: $liveHostCount, in: 0...4)

            if liveHostCount > 0 {
                // The point is to scroll this while the apps are live. One
                // live host is the minimum the design needs; three is the
                // target. Watch for dropped frames here, then confirm with
                // Instruments — a screen cannot measure its own FPS honestly.
                ForEach(0..<liveHostCount, id: \.self) { index in
                    SpiralAppSpikeRow(index: index)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }
        } header: {
            Text("Performance")
                .compoundListSectionHeader()
        } footer: {
            Text("Scroll this list with the hosts live. Confirm frame timing in Instruments; do not trust an on-screen counter.")
                .compoundListSectionFooter()
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        ForEach(reports, id: \.title) { entry in
            Section {
                ForEach(groups(of: entry.report), id: \.0) { group, results in
                    DisclosureGroup("\(group) — \(summary(results))") {
                        ForEach(results, id: \.name) { result in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(result.name)
                                        .font(.compound.bodySMSemibold)
                                    Spacer()
                                    Text(result.verdict)
                                        .font(.compound.bodySMSemibold)
                                        .foregroundStyle(result.verdict == "blocked"
                                            ? Color.compound.textSuccessPrimary
                                            : Color.compound.textCriticalPrimary)
                                }
                                Text(result.detail)
                                    .font(.compound.bodyXS)
                                    .foregroundStyle(Color.compound.textSecondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(entry.title)
                    Spacer()
                    Text(entry.report.pass ? "PASS" : "FAIL")
                        .foregroundStyle(entry.report.pass
                            ? Color.compound.textSuccessPrimary
                            : Color.compound.textCriticalPrimary)
                }
                .compoundListSectionHeader()
            }
        }
    }

    private func groups(of report: SpiralAppSpikeRunner.ProbeReport)
        -> [(String, [SpiralAppSpikeRunner.CheckResult])] {
        [("network", report.network), ("escape", report.escape),
         ("resource", report.resource), ("leak", report.leak)]
    }

    private func summary(_ results: [SpiralAppSpikeRunner.CheckResult]) -> String {
        let bad = results.filter { $0.verdict != "blocked" }.count
        return bad == 0 ? "all blocked" : "\(bad) NOT blocked"
    }

    // MARK: - Evidence

    @ViewBuilder
    private var evidenceSection: some View {
        if !reports.isEmpty {
            Section {
                ListRow(label: .default(title: "Copy markdown for the walkthrough",
                                        icon: \.copy),
                        kind: .button {
                            UIPasteboard.general.string = reports
                                .map { SpiralAppSpikeRunner.markdown(for: $0.report, title: $0.title) }
                                .joined(separator: "\n\n")
                        })
            } footer: {
                Text("Paste into docs/walkthroughs/0066-runtime-spike.md. Attach an Instruments trace and a packet capture separately — an `inconclusive` verdict is only resolved by a capture.")
                    .compoundListSectionFooter()
            }
        }
    }

    // MARK: - Actions

    private func runOnce() async {
        status = .running("probe")
        failure = nil
        do {
            let report = try await runner.runOnce()
            reports.append((title: "Single run", report: report))
        } catch {
            failure = error.localizedDescription
        }
        status = .done
    }

    private func runReuse() async {
        status = .running("reuse check")
        failure = nil
        do {
            let (first, second) = try await runner.runReuseCheck()
            reports.append((title: "Reuse — first mount", report: first))
            reports.append((title: "Reuse — second mount (same web view)", report: second))
        } catch {
            failure = error.localizedDescription
        }
        status = .done
    }
}

/// One live host embedded in the list, so the performance half runs against
/// a recycled container rather than a static screen.
///
/// Each row **mounts the probe**, which matters: an empty shell renders
/// nothing, costs almost nothing, and would produce a falsely optimistic
/// scroll measurement. The probe is the heaviest artifact available — React,
/// a full compile, and thirty checks — so it is a fair stand-in for a real
/// app until the conformance harness exists.
private struct SpiralAppSpikeRow: UIViewRepresentable {
    let index: Int

    func makeUIView(context: Context) -> UIView {
        context.coordinator.host.containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(index: index)
    }

    @MainActor
    final class Coordinator {
        let host: SpiralAppWebViewHost

        init(index: Int) {
            host = SpiralAppWebViewHost(allowsSpikeProbe: true) { method, _, _ in
                switch method {
                case SpiralAppCapability.appContextRead.rawValue:
                    SpiralAppBridge.success(["instanceId": "perf-\(index)"])
                default:
                    SpiralAppBridge.failure(code: "unavailable", message: "performance row")
                }
            }

            Task { [host] in
                guard let artifact = Self.probeArtifact() else { return }
                // A distinct instance id per row; the artifact — and so the
                // origin — is deliberately the same, because that is what a
                // timeline full of one popular app looks like.
                try? await host.mount(SpiralAppMount(instanceID: "perf-\(index)",
                                                     artifact: artifact,
                                                     capabilities: SpiralAppCapability.production + [.spikeReport]))
            }
        }

        private static func probeArtifact() -> SpiralAppArtifact? {
            guard let packed = SpiralAppShell.spikeProbeArtifact else { return nil }
            return SpiralAppArtifact.verified(packed: packed.bytes, claimedDigest: packed.digest)
        }
    }
}

#endif
