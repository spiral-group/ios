//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.15): what the registry's tests stand on.
//

import Combine
import Foundation
import MatrixRustSDK
@testable import Spiral
import SpiralAppTestArtifacts
import Testing
import UIKit

#if DEBUG

extension SpiralAppHostRegistryTests {
    /// Everything one test needs, wired the way the app wires it.
    final class World {
        let loader = MediaLoaderMock()
        /// The room the posts are in: its relations are what a session reads.
        let room = JoinedRoomProxyMock(.init(id: "!room:spiral.md"))
        let registry: SpiralAppHostRegistry
        let post: SpiralAppPost
        private let counts = Counts()
        /// A real window, because "visible" means "in a window" and nothing
        /// less. Surfaces are added to it to appear and removed to disappear.
        @MainActor let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        /// What stands for the timeline's table in the tests that move it.
        @MainActor private lazy var table: UIScrollView = {
            let table = UIScrollView(frame: window.bounds)
            table.contentSize = CGSize(width: 400, height: 10000)
            window.addSubview(table)
            return table
        }()
        @MainActor private var surfaces: [String: SpiralAppSurface] = [:]
        @MainActor private var viewers: [String: SpiralAppSurface] = [:]

        /// Put a post's row in the hierarchy but BELOW the window — what a
        /// timeline does with rows just past the viewport. In a window, not on
        /// screen.
        @MainActor
        func showOffScreen(_ eventID: String) {
            let surface = SpiralAppSurface(frame: CGRect(x: 0, y: 2000, width: 300, height: 200))
            surface.registry = registry
            surface.post = post
            surface.eventID = eventID
            surfaces[eventID] = surface
            window.addSubview(surface)
        }

        /// Put a post's row on screen. The surface reports itself from
        /// `didMoveToWindow`, exactly as the timeline's does.
        @MainActor
        /// A row hanging off the bottom edge with only `visible` points of its
        /// 200 inside the window — what the reader sees as a sliver.
        func showPartly(_ eventID: String, visible: CGFloat) {
            let surface = SpiralAppSurface(frame: CGRect(x: 0, y: window.bounds.height - visible, width: 300, height: 200))
            surface.registry = registry
            surface.post = post
            surface.eventID = eventID
            surfaces[eventID] = surface
            window.addSubview(surface)
        }

        /// `mayRun: false` is a reader who hid media: the row may not run its app.
        func show(_ eventID: String, mayRun: Bool = true, post: SpiralAppPost? = nil) {
            let surface = SpiralAppSurface(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
            surface.mayRunAutomatically = mayRun
            surface.registry = registry
            surface.post = post ?? self.post
            surface.eventID = eventID
            surfaces[eventID] = surface
            window.addSubview(surface)
        }

        /// Scroll a row past the viewport, keeping it in the window.
        func moveOffScreen(_ eventID: String) {
            surfaces[eventID]?.frame.origin.y = 2000
        }

        /// `show`, inside the table, `below` points under the top of what it shows.
        func showInTable(_ eventID: String, below: CGFloat = 0) {
            let surface = SpiralAppSurface(frame: CGRect(x: 0, y: table.contentOffset.y + below, width: 300, height: 200))
            surface.registry = registry
            surface.post = post
            surface.eventID = eventID
            surfaces[eventID] = surface
            table.addSubview(surface)
        }

        /// A cell the table keeps for reuse: HIDDEN, in the table and so in the
        /// window, at a frame `below` points under the top of what the table
        /// shows, still holding the post it last showed (question 411). Returns
        /// the cell's surface; its superview is the cell.
        func showHiddenInTable(_ eventID: String, below: CGFloat = 0) -> SpiralAppSurface {
            let cell = UIView(frame: CGRect(x: 0, y: table.contentOffset.y + below, width: 300, height: 200))
            cell.isHidden = true
            table.addSubview(cell)
            let surface = SpiralAppSurface(frame: cell.bounds)
            surface.registry = registry
            surface.post = post
            surface.eventID = eventID
            cell.addSubview(surface)
            return surface
        }

        /// Move the table a little every frame, as a finger or a slow drift does
        /// (one point a frame is about 60 pt/s).
        func scrollTable(for duration: Duration) async {
            let end = ContinuousClock.now + duration
            while ContinuousClock.now < end {
                table.contentOffset.y += 1
                try? await Task.sleep(for: .milliseconds(16))
            }
        }

        /// Move the table fast, as a fling does, back and forth so its rows stay
        /// where they were (40 points a frame is about 2,500 pt/s).
        func flingTable(for duration: Duration) async {
            let end = ContinuousClock.now + duration
            var step: CGFloat = 40
            while ContinuousClock.now < end {
                table.contentOffset.y += step
                step = -step
                try? await Task.sleep(for: .milliseconds(16))
            }
        }

        /// The table re-hosting a row mid-scroll: out of its window and straight back.
        func bounce(_ eventID: String) {
            guard let surface = surfaces[eventID], let parent = surface.superview else { return }
            surface.removeFromSuperview()
            parent.addSubview(surface)
        }

        /// Take a post's row off screen.
        @MainActor
        func hide(_ eventID: String) {
            surfaces[eventID]?.removeFromSuperview()
            surfaces[eventID] = nil
        }

        /// Make the next mount fail with this error.
        @MainActor
        func failNextMount(_ error: Error) {
            counts.mountFailures.append(error)
        }

        var snapshotsTaken: Int {
            counts.snapshots
        }

        /// From now on a picture of an app comes back one colour, as WebKit's
        /// does for a web view scrolled out of the window.
        func takeBlankSnapshots(_ isBlank: Bool = true) {
            counts.blankSnapshots = isBlank
        }

        /// The full-screen viewer for a post: a surface over the whole window.
        func showViewer(_ eventID: String) {
            let surface = SpiralAppSurface(frame: window.bounds)
            surface.viewportMode = .expanded
            surface.registry = registry
            surface.post = post
            surface.eventID = eventID
            viewers[eventID] = surface
            window.addSubview(surface)
        }

        func hideViewer(_ eventID: String) {
            viewers[eventID]?.removeFromSuperview()
            viewers[eventID] = nil
        }

        func viewer(_ eventID: String) -> SpiralAppSurface? {
            viewers[eventID]
        }

        /// Pages asked to lay out at a new size don't, until `releaseLayout`.
        func holdLayout() {
            counts.layoutGate = false
        }

        func releaseLayout() {
            counts.layoutGate = true
        }

        var layoutsAsked: [(size: CGSize, viewport: String?)] {
            counts.layouts
        }

        /// Pages coming back don't draw until `releasePaint`.
        func holdPaint() {
            counts.paintGate = false
        }

        func releasePaint() {
            counts.paintGate = true
        }

        /// From now on a page coming back never draws.
        func stopPainting() {
            counts.paintFails = true
        }

        /// Hold the artifact's download until `releaseArtifact`.
        func holdArtifact() {
            let bytes = loader.loadMediaContentForSourceClosure
            let counts = counts
            counts.artifactGate = false
            loader.loadMediaContentForSourceClosure = { source in
                while await !counts.artifactGate {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return try await bytes?(source) ?? Data()
            }
        }

        func releaseArtifact() {
            counts.artifactGate = true
        }

        /// The next host's shell never comes.
        @MainActor
        func failNextShell() {
            counts.shellFailures += 1
        }

        @MainActor
        var mountAttempts: Int {
            counts.mountAttempts
        }

        /// What the row for this post is showing, or nil for the card.
        @MainActor
        func presented(_ eventID: String) -> UIView? {
            surfaces[eventID]?.presented
        }

        @MainActor
        func surface(_ eventID: String) -> SpiralAppSurface? {
            surfaces[eventID]
        }

        var hostsMade: Int {
            counts.made
        }

        var destroyed: Int {
            counts.destroyed
        }

        @MainActor
        var lastHost: FakeHost? {
            counts.lastHost as? FakeHost
        }

        @MainActor
        init(maxLiveHosts: Int = SpiralAppHostRegistry.defaultMaxLiveHosts,
             unmountDeadline: Duration = .seconds(2)) throws {
            let packed = try #require(SpiralAppTestArtifacts.conformance)
            loader.loadMediaContentForSourceClosure = { _ in packed.bytes }

            post = SpiralAppPost(InteractivePostContent(body: "Conformance",
                                                        appId: "conformance",
                                                        runtime: "1",
                                                        title: "Conformance",
                                                        aspect: "4:3",
                                                        stateChannel: "default",
                                                        sha256: packed.digest,
                                                        url: "mxc://spiral.md/abcdef",
                                                        fileJson: nil))

            // A room that answers the two Spiral calls a session makes. The
            // subscription is refused on purpose: a post without live updates
            // still reads and still writes, and these tests are about the
            // registry's policy, not about delivery.
            room.loadSpiralAppRelationsForReturnValue = .success([])
            room.subscribeToSpiralEventsTypesListenerReturnValue = .failure(.sdkError(SpiralAppTestError.noSubscription))

            let counts = counts
            registry = SpiralAppHostRegistry(artifacts: .init(mediaLoader: loader),
                                             roomProxy: room,
                                             maxLiveHosts: maxLiveHosts,
                                             unmountDeadline: unmountDeadline) {
                counts.made += 1
                return FakeHost(counts: counts)
            }
        }

        /// The same post after an edit: the conformance app with one more
        /// line, served at its own address, so its digest is its own.
        func editedPost() throws -> SpiralAppPost {
            let packed = try #require(SpiralAppTestArtifacts.conformance)
            let container = try #require(SpiralAppContainer.unpack(packed.bytes))
            let capabilities = try String(decoding: JSONSerialization.data(withJSONObject: container.manifest.capabilities), as: UTF8.self)
            let manifestJSON = #"{"app_id":"conformance","runtime":"1","entry":"app.jsx","aspect":"4:3","state_channel":"default","capabilities":\#(capabilities),"limits":{"max_state_bytes":16384}}"#
            let edited = SpiralAppContainer.pack(manifestJSON: manifestJSON,
                                                 entry: container.manifest.entry,
                                                 source: String(decoding: container.source, as: UTF8.self) + "\n// edited\n")
            let original = packed.bytes
            loader.loadMediaContentForSourceClosure = { source in
                source.url.absoluteString.contains("edited") ? edited : original
            }
            return SpiralAppPost(InteractivePostContent(body: "Conformance",
                                                        appId: "conformance",
                                                        runtime: "1",
                                                        title: "Conformance",
                                                        aspect: "4:3",
                                                        stateChannel: "default",
                                                        sha256: SpiralAppArtifact.digest(of: edited),
                                                        url: "mxc://spiral.md/edited",
                                                        fileJson: nil))
        }

        /// Long enough for the arming to fire and the mount to finish.
        /// Stand in for the system killing the live host's content process.
        func killContentProcess() {
            (counts.lastHost as? FakeHost)?.onContentProcessDied?()
        }

        func settle() async throws {
            try await Task.sleep(for: .milliseconds(400))
        }

        /// Until the row shows its app, or a deadline a loaded Mac can't reach
        /// by being slow. For a test that must see it arrive.
        func untilPresented(_ eventID: String) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while presented(eventID) == nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        /// Long enough for a row to have taken a running app back.
        func settleOnReturn() async throws {
            try await Task.sleep(for: .milliseconds(120))
        }

        /// Hold every host at `waitUntilReady`, so a test can look at the world
        /// as it is WHILE an app is starting rather than after.
        @MainActor func blockStart() {
            counts.startGate = false
        }

        @MainActor func unblockStart() {
            counts.startGate = true
        }

        /// From now on no app leaves when told to.
        @MainActor func wedgeUnmounts() {
            counts.unmountHangs = true
        }
    }

    enum SpiralAppTestError: Error, CustomStringConvertible {
        case noSubscription
        /// Reads the way the real one does: the shell's word for "a newer
        /// mount replaced you", carried out through a `WKError` description.
        case superseded
        /// An artifact that will not run however many times it is asked.
        case broken

        var description: String {
            switch self {
            case .noSubscription: "noSubscription"
            case .superseded: "Error: \(SpiralAppShellContract.abandoned)"
            case .broken: "the artifact refused to start"
            }
        }
    }

    final class Counts: @unchecked Sendable {
        var made = 0
        var destroyed = 0
        /// When false, hosts never finish becoming ready.
        @MainActor var startGate = true
        /// Errors the next mounts should throw, oldest first. Empty means
        /// every mount succeeds.
        @MainActor var mountFailures: [Error] = []
        /// How many mounts were attempted, whatever they returned.
        @MainActor var mountAttempts = 0
        /// The most recently built host, so a test can read what it was told.
        @MainActor var lastHost: AnyObject?
        /// When true, an unmount never returns — `while (true) {}` in a frame.
        @MainActor var unmountHangs = false
        /// When false, the artifact's download waits.
        @MainActor var artifactGate = true
        /// How many pictures of an app were taken.
        @MainActor var snapshots = 0
        @MainActor var blankSnapshots = false
        /// When false, a page coming back doesn't draw until it is true.
        @MainActor var paintGate = true
        /// While false, a page asked to lay itself out at a size doesn't.
        @MainActor var layoutGate = true
        /// Each size a page was asked to lay out at, with the last viewport it had been told.
        @MainActor var layouts: [(size: CGSize, viewport: String?)] = []
        /// When true, a page coming back never draws.
        @MainActor var paintFails = false
        /// How many of the next hosts never get a shell.
        @MainActor var shellFailures = 0
    }

    /// A session that answers nothing. Enough to build an instance, which is
    /// all a teardown test needs.
    @MainActor
    final class SilentSession: SpiralAppSessionProtocol {
        var snapshotPublisher: AnyPublisher<SpiralAppStateReader.Snapshot, Never> {
            Empty().eraseToAnyPublisher()
        }

        var context: [String: Any] {
            [:]
        }

        func members() async -> [String: Any] {
            [:]
        }

        var snapshot: SpiralAppStateReader.Snapshot {
            .loading
        }

        func apply(_ operation: SpiralAppOperation, summary: [String: Any]?, touched: Bool) async -> Result<Void, SpiralAppPostError> {
            .success(())
        }

    }

    /// A picture of an app: two colours, or one when `isBlank`.
    @MainActor
    static func picture(isBlank: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            guard !isBlank else { return }
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 20))
        }
    }

    /// A host that does everything but touch WebKit.
    @MainActor
    final class FakeHost: SpiralAppHostProtocol {
        let containerView = UIView(frame: .zero)
        /// Recorded so a test can ask whether a running app was TOLD about a
        /// change. A fake that silently swallowed pushes is why the timeline
        /// never forwarded them and no test noticed.
        private(set) var pushes: [[String: Any]] = []
        var onContentProcessDied: (@MainActor () -> Void)?
        /// What the bridge would call right now, or nil when unbound. A test
        /// reads this to check a parked host cannot reach a session.
        private(set) var boundHandler: SpiralAppMethodHandler?
        private(set) var unmounts = 0
        private let counts: Counts

        init(counts: Counts) {
            self.counts = counts
            counts.lastHost = self
        }

        func waitUntilReady() async throws {
            while !counts.startGate {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if counts.shellFailures > 0 {
                counts.shellFailures -= 1
                onContentProcessDied?()
                throw SpiralAppHostError.shellUnavailable
            }
        }

        func bind(_ handler: @escaping SpiralAppMethodHandler) {
            boundHandler = handler
        }

        func mount(_ mount: SpiralAppMount) async throws {
            counts.mountAttempts += 1
            if !counts.mountFailures.isEmpty {
                throw counts.mountFailures.removeFirst()
            }
        }

        func push(_ message: [String: Any]) async {
            pushes.append(message)
        }

        func unmount() async {
            boundHandler = nil
            unmounts += 1
            if counts.unmountHangs {
                try? await Task.sleep(for: .seconds(3600))
            }
        }

        func destroy() {
            counts.destroyed += 1
        }

        func takeSnapshot(_ completion: @escaping (UIImage?) -> Void) {
            counts.snapshots += 1
            completion(SpiralAppHostRegistryTests.picture(isBlank: counts.blankSnapshots))
        }

        func waitForPaint() async -> Bool {
            while !counts.paintGate {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return !counts.paintFails
        }

        /// Records what it was asked, and what the app had been told by then.
        func waitForLayout(_ size: CGSize) async -> Bool {
            counts.layouts.append((size, pushes.last?["mode"] as? String))
            while !counts.layoutGate {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return await waitForPaint()
        }
    }
}

#endif
