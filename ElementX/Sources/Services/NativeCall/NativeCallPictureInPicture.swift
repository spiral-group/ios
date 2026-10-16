//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): system Picture in Picture for native video
// calls — attempt 2. Attempt 1 (`3c1f68444`, reverted) died of twelve
// lifecycle defects; the constraints it proved are recorded in
// `docs/project/DESIGNS/native-call-pip.md` and every structural choice
// below cites the defect it answers.
//
// Scope is the operator's Option C: the floating window shows the REMOTE
// party; the local camera pauses while the app is backgrounded (the
// capture session cannot legally gain multitasking access after it has
// started — AVCaptureSession.h:545 — so pretending otherwise showed the
// peer a frozen frame while our logs looked healthy).

import AVKit
import Combine
import SwiftUI

enum NativeCallPictureInPictureAction {
    /// The floating window took over; the full screen should step aside.
    case started
    /// The user tapped the window's restore affordance: bring the call
    /// screen back. This is the ONLY signal that expands the screen — a
    /// window closed with ✕ (or a failed start) must not resurrect a call
    /// screen the user dismissed (attempt-1 C6).
    case restoreRequested
}

/// Owns the system PiP session for one call screen.
@MainActor
final class NativeCallPictureInPictureController: NSObject {
    /// What the floating window should show. `source` nil means "no remote
    /// picture right now" — the identity placeholder renders instead.
    /// `identityKey` participates so that two camera-off participants in a
    /// row still swap the placeholder (attempt-1 C5b: deduplicating on the
    /// nil source alone kept the previous person's face up).
    struct Content: Equatable {
        var source: NativeCallVideoSource?
        var identityKey: String
    }

    private let actionsSubject: PassthroughSubject<NativeCallPictureInPictureAction, Never> = .init()
    var actions: AnyPublisher<NativeCallPictureInPictureAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }

    private weak var renderer: NativeCallVideoRendering?
    private var controller: AVPictureInPictureController?
    private let contentViewController = AVPictureInPictureVideoCallViewController()
    /// The view AVKit animates from and, more importantly, the one it
    /// consults when the app goes to the background to decide whether to
    /// auto-start. It is OWNED here, not by SwiftUI: the call screen's
    /// tree is rebuilt on every overlay transition and a SwiftUI-owned
    /// anchor died before AVKit looked at it (`activeVideoCallSourceView`
    /// is weak), so the automatic start silently never happened — the
    /// minimal Block E smoke on 2026-09-14, `anchor … window nil` on every
    /// rebind. The SwiftUI side merely mounts this same view.
    let anchorView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }()

    private var desiredContent: Content?
    private var placeholderBuilder: (() -> AnyView)?

    /// What is physically installed in the window right now, and whether it
    /// is the placeholder. The placeholder flag is part of the key so that
    /// a track landing AFTER the window opened upgrades the placeholder to
    /// the picture instead of pinning forever (attempt-1 C5: deduplicating
    /// on the REQUEST rather than the RESULT).
    private var installed: (content: Content, isPlaceholder: Bool)?
    private var installedVideoView: UIView?
    /// Retained deliberately: handing out `UIHostingController().view`
    /// without keeping the controller is the classic dead-view bug
    /// (attempt-1 S3).
    private var installedHostingController: UIViewController?

    /// Content exists only between `willStart` and `didStop` (attempt-1
    /// C8): an installed sample-buffer view renders every frame all call
    /// long otherwise — a second full render path on the codepath the
    /// thermal work of the same day was trimming.
    private(set) var isActive = false

    /// Once the call is over this object is inert: a `makeUIView` landing
    /// between `invalidate()` and the view tree unmounting must not
    /// resurrect a controller (with auto-start armed) bound to a dead call
    /// (critic-2 N3).
    private var isInvalidated = false

    /// How many hosted placeholders the window currently owns — lets a test
    /// see an install/uninstall without a view hierarchy.
    var contentChildCount: Int {
        contentViewController.children.count
    }

    init(renderer: NativeCallVideoRendering?) {
        self.renderer = renderer
        super.init()

        // Portrait phone camera frames (the capture is 720p, framed
        // 720×1280 in portrait). AVKit shapes the window from this size
        // for the video-call content source; it is not inferred from
        // frames (attempt-1 C7 had it backwards, in both number and
        // comment).
        contentViewController.preferredContentSize = CGSize(width: 720, height: 1280)
    }

    /// Creates the PiP session bound to the owned anchor. Idempotent: the
    /// SwiftUI mount point calls this whenever its tree is rebuilt, and the
    /// controller must NOT be recreated (a fresh controller re-arms
    /// auto-start against a source AVKit has not laid out yet).
    func attach() {
        guard !isInvalidated, controller == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            MXLog.info("Picture in Picture is unsupported on this device")
            return
        }
        MXLog.info("Picture in Picture controller CREATE; anchor \(Self.describe(anchorView))")

        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: anchorView,
                                                                contentViewController: contentViewController)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        // The Telegram behaviour the operator asked for: swiping home during
        // a video call starts PiP by itself, with no button to find.
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller
        // AVKit's readiness is the one fact the device smoke needs when
        // auto-start silently does nothing.
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in
                MXLog.info("Picture in Picture possible: \(possible)")
            }
        }
    }

    private var possibleObservation: NSKeyValueObservation?

    private static func describe(_ view: UIView) -> String {
        "frame \(view.frame.integral) window \(view.window == nil ? "nil" : "set") superview \(view.superview == nil ? "nil" : "set") hidden \(view.isHidden)"
    }

    /// Records what the window should show. While the window is up, a
    /// change (stage swap, camera toggle, the track finally resolving)
    /// re-installs; while it is down, this is just bookkeeping for the
    /// next `willStart`.
    func setContent(_ content: Content, placeholder: @escaping () -> AnyView) {
        guard !isInvalidated else { return }
        desiredContent = content
        placeholderBuilder = placeholder
        refreshInstalledContentIfNeeded()
    }

    /// The call stopped being a video call (everyone's camera went off —
    /// `isVideoCall` is live state, not a birth fact). PiP is a video
    /// affordance by the operator's decision, so the window must come down
    /// rather than float a stale tile over an audio call (critic-2 N2).
    func contentBecameUnavailable() {
        desiredContent = nil
        placeholderBuilder = nil
        uninstallContent()
        controller?.stopPictureInPicture()
    }

    /// Stops the floating window because the full call screen is coming
    /// back by a route that is NOT the window's own restore button — the
    /// call bar tap, a same-room re-entry. Without this the screen and the
    /// window showed the same call twice (critic-2 N1).
    func stopForFullScreenReturn() {
        controller?.stopPictureInPicture()
    }

    /// Starts PiP explicitly — the notification-navigation path, where the
    /// app stays foreground but the call screen must get out of the way.
    func start() {
        guard let controller, controller.isPictureInPicturePossible, !controller.isPictureInPictureActive else {
            return
        }
        controller.startPictureInPicture()
    }

    /// Tears the session down when the call ends.
    ///
    /// `stopPictureInPicture()` is called UNCONDITIONALLY (not guarded on
    /// `isPictureInPictureActive`): a call that ends during the start
    /// transition — peer hangs up as the user swipes home — is not
    /// "active" yet, and skipping the stop there orphans the window
    /// (attempt-1 C9). Nil-ing `contentSource` is AVKit's documented
    /// end-of-call contract (`AVPictureInPictureController_VideoCallSupport.h:28`).
    func invalidate() {
        isInvalidated = true
        controller?.stopPictureInPicture()
        uninstallContent()
        isActive = false
        controller?.contentSource = nil
        controller?.delegate = nil
        possibleObservation = nil
        controller = nil
        desiredContent = nil
        placeholderBuilder = nil
    }

    // MARK: - Window lifecycle (internal so tests can drive it without AVKit)

    func handleWillStart() {
        isActive = true
        installContent()
    }

    func handleDidStop() {
        isActive = false
        uninstallContent()
    }

    // MARK: - Content

    private func refreshInstalledContentIfNeeded() {
        guard isActive, let desiredContent else { return }
        let canRenderVideo = desiredContent.source.map { renderer?.canRenderPictureInPictureVideo(for: $0) ?? false } ?? false
        if let installed, installed.content == desiredContent, installed.isPlaceholder == !canRenderVideo {
            return
        }
        installContent()
    }

    private func installContent() {
        uninstallContent()
        guard let desiredContent else { return }

        let content: UIView
        var isPlaceholder = false
        if let source = desiredContent.source, let videoView = renderer?.pictureInPictureVideoView(for: source) {
            installedVideoView = videoView
            content = videoView
        } else {
            isPlaceholder = true
            let hosting = UIHostingController(rootView: placeholderBuilder?() ?? AnyView(Color.black))
            hosting.view.backgroundColor = .black
            contentViewController.addChild(hosting)
            installedHostingController = hosting
            content = hosting.view
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        contentViewController.view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: contentViewController.view.topAnchor),
            content.bottomAnchor.constraint(equalTo: contentViewController.view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: contentViewController.view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentViewController.view.trailingAnchor)
        ])
        installedHostingController?.didMove(toParent: contentViewController)

        installed = (desiredContent, isPlaceholder)
    }

    private func uninstallContent() {
        if let installedVideoView {
            // Deregister from the track before the view goes (attempt-1
            // C10): the SDK only releases the renderer when the track is
            // reassigned, never on deallocation.
            renderer?.tearDownPictureInPictureVideoView(installedVideoView)
            installedVideoView.removeFromSuperview()
        }
        installedVideoView = nil

        if let installedHostingController {
            installedHostingController.willMove(toParent: nil)
            installedHostingController.view.removeFromSuperview()
            installedHostingController.removeFromParent()
        }
        installedHostingController = nil

        installed = nil
    }
}

// MARK: - AVPictureInPictureControllerDelegate

// Every method is `nonisolated` with an explicit hop: AVKit does not
// document its delegate queue, and under this target's MainActor default
// isolation an off-main callback into an isolated method TRAPS rather than
// races.
extension NativeCallPictureInPictureController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.handleWillStart()
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        MXLog.info("Picture in Picture started")
        Task { @MainActor in
            self.actionsSubject.send(.started)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Deliberately NOT a "go full screen" signal: the window stopping
        // can mean the user closed it with ✕, wanting neither the window
        // nor the screen (attempt-1 C6). The call stays behind the in-app
        // bar; only `restoreRequested` expands.
        MXLog.info("Picture in Picture stopped")
        Task { @MainActor in
            self.handleDidStop()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        // A failure to start must not touch the UI at all — force-expanding
        // a call the user had minimized because PiP could not start was
        // attempt-1 C6's worst case.
        MXLog.error("Picture in Picture failed to start: \(error)")
        Task { @MainActor in
            self.handleDidStop()
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        Task { @MainActor in
            self.actionsSubject.send(.restoreRequested)
        }
        // Answered on AVKit's own thread: the handler is not Sendable, so it
        // cannot ride into the actor hop — and the restore animation not
        // waiting for our remount is acknowledged cosmetic debt (critic-2
        // N5), not a correctness edge.
        completionHandler(true)
    }
}

// MARK: - The stage anchor

/// Mounts the controller-owned anchor into the call screen's tree.
///
/// A `UIViewRepresentable` because the call screen is SwiftUI and AVKit
/// needs a real `UIView` in the window. The view itself belongs to the
/// controller so that it outlives every SwiftUI rebuild; this wrapper
/// only parents it. Re-parenting a view that is already in a superview
/// is fine — UIKit moves it.
struct NativeCallPictureInPictureAnchor: UIViewRepresentable {
    let controller: NativeCallPictureInPictureController

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.isUserInteractionEnabled = false
        host.backgroundColor = .clear
        mount(in: host)
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        mount(in: uiView)
    }

    func mount(in host: UIView) {
        let anchor = controller.anchorView
        if anchor.superview !== host {
            anchor.removeFromSuperview()
            anchor.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(anchor)
            NSLayoutConstraint.activate([
                anchor.topAnchor.constraint(equalTo: host.topAnchor),
                anchor.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                anchor.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                anchor.trailingAnchor.constraint(equalTo: host.trailingAnchor)
            ])
        }
        controller.attach()
    }
}
