//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.12): does this reader read what
// the packer wrote?
//
// Handwritten fixtures would only prove this file agrees with itself. The
// tests that matter here read the REAL packed artifacts out of the shell
// bundle — bytes produced by the TypeScript packer, in the build that ships —
// and check that the digest beside them is the digest of those bytes.
//
// That is the only assertion in the project where two independent
// implementations of one format are compared, and the format exists precisely
// because a third (Rust, for the agent) has to join them.
//

import CryptoKit
@testable import ElementX
import Foundation
import SpiralAppShell
import Testing

struct SpiralAppContainerTests {
    // MARK: - Against the real packer

    #if DEBUG
    @Test
    func everyShippedArtifactUnpacks() throws {
        let shipped: [(String, SpiralAppShell.PackedArtifact?)] = [
            ("counter", SpiralAppShell.sliceCounterArtifact),
            ("conformance", SpiralAppShell.conformanceArtifact),
            ("probe", SpiralAppShell.spikeProbeArtifact)
        ]

        for (name, artifact) in shipped {
            let artifact = try #require(artifact, "\(name) is not in the bundle")
            let container = try #require(SpiralAppContainer.unpack(artifact.bytes),
                                         "\(name) does not unpack")

            #expect(container.manifest.appID == name)
            #expect(container.manifest.entry == "app.jsx")
            #expect(!container.source.isEmpty)
        }
    }

    @Test
    func theDigestBesideEachArtifactIsTheDigestOfItsBytes() throws {
        // The packer writes the digest; this recomputes it. If they ever
        // disagree the mount refuses, which is right — but silently, so the
        // disagreement is worth catching here instead.
        let artifact = try #require(SpiralAppShell.conformanceArtifact)
        let actual = SHA256.hash(data: artifact.bytes).map { String(format: "%02x", $0) }.joined()

        #expect(actual == artifact.digest)
    }

    @Test
    func aShippedArtifactVerifiesAndCarriesItsManifest() throws {
        let packed = try #require(SpiralAppShell.sliceCounterArtifact)
        let artifact = try #require(SpiralAppArtifact.verified(packed: packed.bytes,
                                                               claimedDigest: packed.digest))

        #expect(artifact.manifest.appID == "counter")
        #expect(artifact.runtimeVersion == "1")
        #expect(Self.isRatio(artifact.manifest.aspectRatio, 4.0 / 3.0))
    }
    #endif

    // MARK: - Refusing what it should refuse

    private static func packed(manifest: String, entry: String, source: String) -> Data {
        var bytes = Data("SPIRALv1\n".utf8)
        bytes.append(Data("manifest.json\n\(manifest.utf8.count)\n".utf8))
        bytes.append(Data(manifest.utf8))
        bytes.append(Data("\(entry)\n\(source.utf8.count)\n".utf8))
        bytes.append(Data(source.utf8))
        return bytes
    }

    private static let validManifest = #"""
    {"app_id":"t","runtime":"1","entry":"app.jsx","aspect":"4:3","state_channel":"matrix","capabilities":["state.shared.read"],"limits":{"max_state_bytes":16384}}
    """#

    @Test
    func somethingThatIsNotAContainerSaysSo() {
        #expect(SpiralAppContainer.unpack(Data("PK\u{03}\u{04}".utf8)) == nil)
        #expect(SpiralAppContainer.unpack(Data()) == nil)
    }

    @Test
    func aByteCountLongerThanTheContainerIsRefused() {
        var bytes = Data("SPIRALv1\n".utf8)
        bytes.append(Data("manifest.json\n999\n{}".utf8))

        #expect(SpiralAppContainer.unpack(bytes) == nil)
    }

    @Test
    func bytesAfterTheLastEntryAreRefused() {
        // A digest cannot catch a writer that appends: both sides agree on
        // the hash of the whole thing and disagree about its contents.
        var bytes = Self.packed(manifest: Self.validManifest, entry: "app.jsx", source: "x")
        bytes.append(0x41)

        #expect(SpiralAppContainer.unpack(bytes) == nil)
    }

    @Test
    func anEntryTheManifestDoesNotNameIsRefused() {
        let bytes = Self.packed(manifest: Self.validManifest, entry: "other.jsx", source: "x")
        #expect(SpiralAppContainer.unpack(bytes) == nil)
    }

    @Test
    func aSourceContainingTheFormatsOwnSyntaxSurvives() {
        // A generated app can contain anything, including something shaped
        // like an entry header. Byte counts are what makes that safe; a
        // reader that scanned for names would be fooled by exactly this.
        let trap = "const t = \"app.jsx\\n999\\n\";\nexport default () => t;"
        let bytes = Self.packed(manifest: Self.validManifest, entry: "app.jsx", source: trap)

        let container = SpiralAppContainer.unpack(bytes)
        #expect(String(data: container?.source ?? Data(), encoding: .utf8) == trap)
    }

    // MARK: - The manifest asks; the host grants

    /// Built with `JSONSerialization` rather than interpolation: Swift's
    /// description of `["a"]` is not JSON, and the first version of this
    /// helper produced a manifest that could not parse — so the test failed
    /// for a reason that had nothing to do with capabilities.
    private static func manifest(capabilities: [String]) -> SpiralAppManifest {
        let object: [String: Any] = ["app_id": "t", "runtime": "1",
                                     "entry": "app.jsx", "capabilities": capabilities]
        return SpiralAppManifest(json: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())!
    }

    @Test
    func whatTheManifestAsksForAndTheHostAllowsIsGranted() {
        let granted = SpiralAppCapability.granted(requestedBy: Self.manifest(capabilities: ["state.shared.read"]),
                                                  from: SpiralAppCapability.production)

        #expect(granted == [.stateSharedRead])
    }

    @Test
    func askingForMoreThanTheHostOffersRefusesTheWholeMount() {
        // Not the intersection: an app written against a capability it will
        // not get runs half-working, which is harder to diagnose than one
        // that did not start — especially in a frame whose console reaches
        // nothing.
        #expect(SpiralAppCapability.granted(requestedBy: Self.manifest(capabilities: ["chat.message.send"]),
                                            from: SpiralAppCapability.production) == nil)
    }

    #if DEBUG
    @Test
    func theProbesSpikeChannelIsRefusedByProductionAndGrantedByTheHarness() throws {
        let probe = try #require(SpiralAppShell.spikeProbeArtifact)
        let container = try #require(SpiralAppContainer.unpack(probe.bytes))

        #expect(SpiralAppCapability.granted(requestedBy: container.manifest,
                                            from: SpiralAppCapability.production) == nil)

        let harness = SpiralAppCapability.production + [.spikeReport]
        #expect(SpiralAppCapability.granted(requestedBy: container.manifest, from: harness)?.count == 5)
    }
    #endif

    // MARK: - Aspect

    @Test
    func anAspectBecomesARatioTheRowCanBeSizedFrom() {
        #expect(Self.isRatio(Self.manifestWith(aspect: "4:3").aspectRatio, 4.0 / 3.0))
        #expect(Self.isRatio(Self.manifestWith(aspect: "1:1").aspectRatio, 1))
    }

    @Test
    func nonsenseAspectsAreRefusedRatherThanClamped() {
        // A row sized from a nonsense ratio is a layout bug that surfaces far
        // from its cause.
        #expect(Self.manifestWith(aspect: "0:3").aspectRatio == nil)
        #expect(Self.manifestWith(aspect: "-4:3").aspectRatio == nil)
        #expect(Self.manifestWith(aspect: "wide").aspectRatio == nil)
        #expect(Self.manifestWith(aspect: "4:3:2").aspectRatio == nil)
    }

    private static func manifestWith(aspect: String) -> SpiralAppManifest {
        let object: [String: Any] = ["app_id": "t", "runtime": "1", "entry": "app.jsx",
                                     "aspect": aspect, "capabilities": [String]()]
        return SpiralAppManifest(json: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())!
    }

    /// Floats are compared with a tolerance. A ratio parsed from text and one
    /// written as a literal can differ in the last bit while printing the
    /// same, which makes an exact comparison fail in a way nobody can read.
    private static func isRatio(_ value: CGFloat?, _ expected: CGFloat) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9
    }

    @Test
    func aManifestWithoutAnEntryIsNotAManifest() {
        // Absent is survivable for aspect, channel and limit; not for the
        // name of the module to load.
        #expect(SpiralAppManifest(json: Data(#"{"app_id":"t","runtime":"1","capabilities":[]}"#.utf8)) == nil)
    }

    // MARK: - Packing

    /// The one property the packer exists for: given the manifest text and
    /// the source a shipped artifact carries, it produces that artifact's
    /// bytes — and so its digest — exactly. The fixtures were packed by the
    /// TypeScript packer; the Rust one reproduces them too.
    @Test
    func packingAShippedArtifactsContentsReproducesItsBytesAndDigest() throws {
        for (name, packed) in [("counter", SpiralAppShell.sliceCounterArtifact),
                               ("conformance", SpiralAppShell.conformanceArtifact)] {
            let packed = try #require(packed, "\(name) is not in the bundle")
            let container = try #require(SpiralAppContainer.unpack(packed.bytes))
            let manifestJSON = try #require(Self.manifestText(in: packed.bytes))
            let source = try #require(String(data: container.source, encoding: .utf8))

            let repacked = SpiralAppContainer.pack(manifestJSON: manifestJSON,
                                                   entry: container.manifest.entry,
                                                   source: source)

            #expect(repacked == packed.bytes, "\(name): bytes differ from the shipped artifact")
            #expect(SpiralAppArtifact.digest(of: repacked) == packed.digest, "\(name): digest differs")
        }
    }

    /// The manifest entry's text, exactly as packed — what a draft carries.
    private static func manifestText(in bytes: Data) -> String? {
        guard let header = "SPIRALv1\nmanifest.json\n".data(using: .utf8),
              bytes.starts(with: header) else { return nil }
        let afterHeader = bytes[header.count...]
        guard let newline = afterHeader.firstIndex(of: 0x0A),
              let count = Int(String(decoding: afterHeader[..<newline], as: UTF8.self)) else { return nil }
        let start = afterHeader.index(after: newline)
        return String(data: bytes[start..<(start + count)], encoding: .utf8)
    }
}
