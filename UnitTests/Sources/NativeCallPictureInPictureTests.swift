//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
@testable import Spiral
import SwiftUI
import Testing
import UIKit

/// The PiP session's app-side decisions. The `AVPictureInPictureController`
/// itself is the OS's and cannot start in a test process — the window
/// lifecycle is driven through the same internal entry points the AVKit
/// delegate calls (`handleWillStart`/`handleDidStop`), which is exactly the
/// boundary attempt 1 left untested and paid for.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NativeCallPictureInPictureTests {
    private let renderer: PictureInPictureRendererSpy
    private let controller: NativeCallPictureInPictureController
    private let source = NativeCallVideoSource(identity: "@peer:spiral.md", trackID: "TR_1", isLocal: false)

    init() {
        renderer = PictureInPictureRendererSpy()
        controller = NativeCallPictureInPictureController(renderer: renderer)
    }

    @Test
    func theAnchorIsOwnedByTheControllerAndSurvivesRemounts() {
        // Minimal Block E 2026-09-14: AVKit holds the anchor weakly and
        // consults it as the app backgrounds; a SwiftUI-owned anchor was
        // already dead at that moment and auto-start never fired.
        let firstHost = UIView()
        let secondHost = UIView()
        let representable = NativeCallPictureInPictureAnchor(controller: controller)

        representable.mount(in: firstHost)
        #expect(controller.anchorView.superview === firstHost)

        representable.mount(in: secondHost)
        #expect(controller.anchorView.superview === secondHost, "a rebuilt tree re-parents the SAME view")
        #expect(firstHost.subviews.isEmpty)
    }

    @Test
    func nothingRendersWhileTheWindowIsDown() {
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })

        // Attempt-1 C8: content installed outside willStart/didStop renders
        // every incoming frame all call long — a second full render path in
        // parallel with the on-screen one, for a window nobody can see.
        #expect(renderer.buildRequests.isEmpty)
    }

    @Test
    func theWindowOpeningInstallsTheLatestContent() {
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })

        controller.handleWillStart()

        #expect(renderer.buildRequests == [source])
    }

    @Test
    func theWindowClosingTearsTheRendererDown() {
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()
        let installed = renderer.builtViews.last

        controller.handleDidStop()

        // Attempt-1 C10: the SDK only deregisters a renderer when its track
        // is reassigned — skipping the teardown leaves a dead adapter
        // receiving every frame for the track's whole life.
        #expect(renderer.tornDownViews.count == 1)
        #expect(renderer.tornDownViews.last === installed)
    }

    @Test
    func aPlaceholderUpgradesToThePictureWhenTheTrackLands() {
        renderer.resolvesTracks = false
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()
        #expect(renderer.buildRequests == [source], "the resolve attempt happens even when it will fail")

        // The subscription lands a beat later — the state every call starts
        // in. Attempt-1 C5 deduplicated on the REQUEST, so the placeholder
        // installed by the failed resolve pinned for the rest of the call.
        renderer.resolvesTracks = true
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })

        #expect(renderer.buildRequests == [source, source])
    }

    @Test
    func unchangedContentIsNotRebuilt() {
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()

        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })

        // The call screen re-renders constantly (timer, waves): rebuilding
        // the window's content on every pass would flicker.
        #expect(renderer.buildRequests.count == 1)
    }

    @Test
    func aStageSwapReplacesTheContentAndTearsTheOldViewDown() {
        let second = NativeCallVideoSource(identity: "@other:spiral.md", trackID: "TR_2", isLocal: false)
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()

        controller.setContent(.init(source: second, identityKey: "@other:spiral.md"), placeholder: { AnyView(Color.black) })

        #expect(renderer.buildRequests == [source, second])
        #expect(renderer.tornDownViews.count == 1)
    }

    @Test
    func twoCameraOffParticipantsStillSwapThePlaceholder() {
        controller.setContent(.init(source: nil, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()
        controller.setContent(.init(source: nil, identityKey: "@other:spiral.md"), placeholder: { AnyView(Color.red) })

        // Attempt-1 C5b: keyed on the nil source alone, the second person
        // inherited the first person's face.
        #expect(renderer.buildRequests.isEmpty, "no video was ever resolvable")
        // Both installs happened — observable through the content view
        // controller's children (each placeholder is a retained hosting
        // controller, attempt-1 S3).
        #expect(controller.contentChildCount == 1, "the second placeholder replaced the first")
    }

    @Test
    func invalidatingClearsContentForTheNextCall() {
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()

        controller.invalidate()

        #expect(renderer.tornDownViews.count == 1)
        #expect(controller.contentChildCount == 0)
        #expect(!controller.isActive)
    }

    /// Honest name (critic-2 N6): this drives the willStart→didStop order —
    /// the CLOSED-WINDOW path. The failed-start path shares `handleDidStop`
    /// but arrives without a prior willStart; both must emit nothing.
    @Test
    func aClosingWindowEmitsNoUIAction() {
        var actions: [NativeCallPictureInPictureAction] = []
        let cancellable = controller.actions.sink { actions.append($0) }
        defer { cancellable.cancel() }

        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()
        controller.handleDidStop()

        // Attempt-1 C6 mapped both a closed window and a FAILED start to
        // "bring the call screen back full screen" — resurrecting a screen
        // the user had dismissed. Only an explicit restore may expand.
        #expect(actions.isEmpty)
    }

    @Test
    func aDidStopWithoutAWillStartEmitsNoUIActionEither() {
        var actions: [NativeCallPictureInPictureAction] = []
        let cancellable = controller.actions.sink { actions.append($0) }
        defer { cancellable.cancel() }

        // The failed-start order: no willStart ever arrived.
        controller.handleDidStop()

        #expect(actions.isEmpty)
        #expect(!controller.isActive)
    }

    @Test
    func contentBecomingUnavailableTearsTheWindowContentDown() {
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()

        // Everyone's camera went off: the call stopped being a video call
        // under an open window (critic-2 N2). The stale tile must go.
        controller.contentBecameUnavailable()

        #expect(renderer.tornDownViews.count == 1)
        #expect(controller.contentChildCount == 0)

        // And the next willStart must not resurrect the stale content.
        controller.handleWillStart()
        #expect(renderer.buildRequests.count == 1, "no desired content is left to install")
    }

    @Test
    func anInvalidatedControllerIsInert() {
        controller.invalidate()

        // A makeUIView landing between invalidate() and the view tree
        // unmounting must not arm a controller for a dead call (critic-2
        // N3), and late content must not repopulate it.
        controller.setContent(.init(source: source, identityKey: "@peer:spiral.md"), placeholder: { AnyView(Color.black) })
        controller.handleWillStart()

        #expect(renderer.buildRequests.isEmpty)
        #expect(controller.contentChildCount == 0)
    }
}

@MainActor
private final class PictureInPictureRendererSpy: NativeCallVideoRendering {
    var resolvesTracks = true
    private(set) var buildRequests: [NativeCallVideoSource] = []
    private(set) var builtViews: [UIView] = []
    private(set) var tornDownViews: [UIView] = []

    func videoView(for source: NativeCallVideoSource) -> AnyView? {
        nil
    }

    func canRenderPictureInPictureVideo(for source: NativeCallVideoSource) -> Bool {
        resolvesTracks
    }

    func pictureInPictureVideoView(for source: NativeCallVideoSource) -> UIView? {
        buildRequests.append(source)
        guard resolvesTracks else { return nil }
        let view = UIView()
        builtViews.append(view)
        return view
    }

    func tearDownPictureInPictureVideoView(_ view: UIView) {
        tornDownViews.append(view)
    }
}
