//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007): the small value types the
// Interactive Post runtime passes around. Deliberately separate from the
// scheme handler and the pool so those two files stay about one thing each.
//

import CryptoKit
import Foundation

/// A capability an app may be granted. v1 is exactly four, and none of them
/// acts outside the post — which is what makes rendering without a tap safe
/// (ADR-0007 § 4.6).
nonisolated enum SpiralAppCapability: String, CaseIterable {
    case appContextRead = "app.context.read"
    case membersBasicRead = "members.basic.read"
    case stateSharedRead = "state.shared.read"
    case stateSharedWrite = "state.shared.write"
    /// This phone's own corner of the post, for a sealed move (§ 5.78). Reads
    /// nothing about the room and sends nothing to it.
    case statePrivateRead = "state.private.read"
    case statePrivateWrite = "state.private.write"
    /// A clock the room agrees on, more or less. See `SpiralAppSessionProtocol.time`.
    case timeRead = "time.read"

    /// The tap answered in the hand. Writes nothing, reads nothing.
    case uiHaptic = "ui.haptic"
    /// "Give me the whole screen" — a board in a 322-point row becomes a game.
    case uiExpand = "ui.expand"

    #if DEBUG
    /// Carries the Brief 0066 probe's findings out of the sandboxed frame.
    ///
    /// The frame is genuinely opaque — its report cannot be read from the
    /// shell — so it travels the normal validated path instead of a side
    /// channel. Never in ``production``, and the case does not exist at all
    /// in a release build.
    case spikeReport = "spike.report"
    #endif

    /// What a real post may be granted.
    ///
    /// Deliberately **not** `allCases`: in a DEBUG build that would include
    /// `spikeReport`, and a mount built from it would hand a production app
    /// the spike channel.
    static var production: [SpiralAppCapability] {
        [.appContextRead, .membersBasicRead, .stateSharedRead, .stateSharedWrite,
         .statePrivateRead, .statePrivateWrite, .timeRead, .uiHaptic, .uiExpand]
    }

    /// Resolve what a manifest asks for against what the host will give.
    ///
    /// The manifest is a REQUEST (design § 5.12). Returning `nil` refuses the
    /// whole mount rather than granting the intersection: an app written
    /// against a capability it will not get would run half-working, and a
    /// half-working app is harder to diagnose than one that did not start —
    /// especially inside a frame whose console reaches nothing.
    static func granted(requestedBy manifest: SpiralAppManifest,
                        from allowed: [SpiralAppCapability]) -> [SpiralAppCapability]? {
        var granted: [SpiralAppCapability] = []

        for name in manifest.capabilities {
            guard let capability = SpiralAppCapability(rawValue: name),
                  allowed.contains(capability) else {
                MXLog.error("[SpiralApp] \(manifest.appID) asks for \(name), which this runtime does not grant")
                return nil
            }
            granted.append(capability)
        }

        return granted
    }
}

/// An immutable artifact: a manifest and the module a model wrote, addressed
/// by the SHA-256 of the packed bytes.
///
/// The digest is not decoration. Nothing is served to a WebView until the
/// bytes hash to the value the Matrix event claimed, so a compromised media
/// repository cannot swap the code out from under an approved post.
///
/// The digest covers the PACKED container, not the module alone — otherwise a
/// manifest could be swapped for one asking for different capabilities while
/// the digest still matched the code.
/// `nonisolated` because verifying is CPU work — a SHA-256 over the whole
/// artifact and a container parse — that must not happen on the main actor,
/// and because a mount is decided off it. Same reasoning as `SpiralAppPost`.
nonisolated struct SpiralAppArtifact: Equatable {
    /// Lowercase hex SHA-256 of the packed container, as it appears in the event.
    let digest: String
    /// What the artifact declares about itself.
    let manifest: SpiralAppManifest
    /// The entry module, UTF-8.
    let source: Data

    /// Runtime contract the artifact declares. Matched against the shell's.
    var runtimeVersion: String {
        manifest.runtime
    }

    /// Host component of the artifact's origin.
    ///
    /// A distinct host per digest gives each app a distinct origin, which is
    /// defence in depth on top of the sandboxed frame's opaque origin: even
    /// if a future change accidentally granted `allow-same-origin`, two apps
    /// would still not share one.
    var originHost: String {
        "a-\(digest)"
    }

    /// Hex SHA-256 of packed bytes — an artifact's identity.
    static func digest(of packed: Data) -> String {
        SHA256.hash(data: packed).map { String(format: "%02x", $0) }.joined()
    }

    /// Verify packed bytes against a claimed digest, then read them.
    ///
    /// Digest first, parse second, and the order matters: parsing unverified
    /// bytes means running a parser over whatever a media repository chose to
    /// return.
    ///
    /// - Returns: the artifact, or `nil` when the bytes do not match or are
    ///   not a container — the caller must treat `nil` as "refuse to run",
    ///   never as "try anyway".
    static func verified(packed: Data, claimedDigest: String) -> SpiralAppArtifact? {
        let actual = digest(of: packed)
        guard actual == claimedDigest.lowercased() else {
            MXLog.error("[SpiralApp] artifact digest mismatch: claimed \(claimedDigest), got \(actual)")
            return nil
        }

        guard let container = SpiralAppContainer.unpack(packed) else { return nil }

        return SpiralAppArtifact(digest: actual,
                                 manifest: container.manifest,
                                 source: container.source)
    }
}

/// One app instance being mounted into a pooled web view.
nonisolated struct SpiralAppMount: Equatable {
    /// Identifies the post this instance belongs to; the Matrix event id in
    /// production, a synthetic value in the spike.
    let instanceID: String
    let artifact: SpiralAppArtifact
    let capabilities: [SpiralAppCapability]
    /// Whose phone this is. Handed to the app at mount rather than through a
    /// round trip, because it needs it in render to find its own namespace
    /// under `by.<viewerID>` (owned paths). The spike and the harness pass
    /// a placeholder; a post passes the session's user.
    var viewerID = "@spike:local"
    /// The language the app is shown in, as a primary subtag — "uk", "ru",
    /// "en". Handed over at mount like the viewer, so a post can speak it
    /// from the first frame: a catalogue template is read by a whole room,
    /// each member in their own app language (§ 5.60).
    var language = SpiralAppMount.appLanguage

    /// The first of the app's own languages, reduced to its primary subtag.
    static var appLanguage: String {
        let preferred = Bundle.overrideLocalizations?.first ?? Bundle.app.preferredLocalizations.first ?? "en"
        return preferred.split(separator: "-").first.map { $0.lowercased() } ?? "en"
    }

    /// URL of the document the scheme handler synthesises for this artifact.
    var documentURL: URL {
        // Force-unwrap is safe: the components are a fixed scheme and a
        // hex digest, so this cannot fail to parse.
        URL(string: "\(SpiralAppScheme.scheme)://\(artifact.originHost)/index.html")!
    }
}

nonisolated enum SpiralAppScheme {
    /// Custom scheme so WebKit routes every load through our handler. It must
    /// not be `http`/`https`: those are reserved and cannot be intercepted.
    static let scheme = "spiral-app"

    /// Origin host of the trusted shell. Distinct from every artifact host.
    static let shellHost = "shell"

    static var shellDocumentURL: URL {
        URL(string: "\(scheme)://\(shellHost)/index.html")!
    }
}
