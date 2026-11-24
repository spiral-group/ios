//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, decision 344): the status bar's ink over the green call bar. The overlay window sits above
// the app, so its root controller owns the status bar's look. It asks for white only while a call bar is in a window
// and nothing full-screen covers it. Everything else, a bar it doesn't know of included, is the system's default, which
// reads 4.67:1 on the green, so a miss here is passing black and never white on white.
//

import SwiftUI

/// The root of the overlay window.
final class OverlayHostingController<Content: View>: UIHostingController<Content>, CallBarStatusBarHost, LightStatusBarHost {
    weak var callBar: UIView? {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }
    
    // AGENT-PLATFORM (1.0.3 onboarding): a screen drawn on a deep colour whatever the appearance, the start screen's blue.
    weak var lightStatusBarScreen: UIView? {
        didSet { setNeedsStatusBarAppearanceUpdate() }
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        if let window = lightStatusBarScreen?.window, !window.isCoveredFullScreen {
            return .lightContent
        }
        guard let window = callBar?.window, !window.isCoveredFullScreen else { return .default }
        return .lightContent
    }
    
    // AGENT-PLATFORM (Brief 0083, question 413): a full-screen cover that hides the status bar, the media viewer
    // with its bars hidden, decides here, as this window's controller is the one the system asks.
    override var childForStatusBarHidden: UIViewController? {
        statusBarCover
    }
    
    // The cover decides the ink too: the viewer is black whatever the app's appearance, and the default style
    // followed this window's light traits, black on black (Opus review, M1).
    override var childForStatusBarStyle: UIViewController? {
        statusBarCover
    }
    
    private var statusBarCover: UIViewController? {
        view.window?.windowScene?.windows.lazy
            .filter { $0 !== self.view.window && !$0.isHidden }
            .compactMap(\.statusBarHidingCover)
            .first
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }
}

/// A controller covering the app that decides when the status bar shows. It calls
/// ``UIViewController/setNeedsStatusBarAppearanceUpdateInScene()`` when that changes.
@MainActor
protocol StatusBarHidingCover: UIViewController { }

extension UIViewController {
    /// Asks the scene's status bar owner, the overlay window's controller, to look again.
    func setNeedsStatusBarAppearanceUpdateInScene() {
        view.window?.windowScene?.windows.forEach { $0.rootViewController?.setNeedsStatusBarAppearanceUpdate() }
    }
}

@MainActor
private protocol CallBarStatusBarHost: UIViewController {
    var callBar: UIView? { get set }
}

@MainActor
private protocol LightStatusBarHost: UIViewController {
    var lightStatusBarScreen: UIView? { get set }
}

private extension UIWindow {
    /// The controller on top of this window, when it is a cover that decides the status bar.
    var statusBarHidingCover: UIViewController? {
        var top = rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top is any StatusBarHidingCover ? top : nil
    }
    
    /// Whether anything but a sheet or an alert is presented in this window. Those leave the status bar over the dimmed green.
    var isCoveredFullScreen: Bool {
        var presented = rootViewController?.presentedViewController
        while let controller = presented {
            if !(controller is UIAlertController || controller.presentationController is UISheetPresentationController) {
                return true
            }
            presented = controller.presentedViewController
        }
        return false
    }
}

/// Goes behind the call bar and tells the overlay window's controller while the bar is in a window.
struct CallBarStatusBarAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> AnchorView {
        AnchorView()
    }
    
    func updateUIView(_ uiView: AnchorView, context: Context) { }
    
    final class AnchorView: UIView {
        private weak var host: (any CallBarStatusBarHost)?
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            host?.callBar = nil
            host = window?.windowScene?.windows.lazy.compactMap { $0.rootViewController as? any CallBarStatusBarHost }.first
            host?.callBar = window == nil ? nil : self
        }
    }
}

// MARK: - Light status bar (AGENT-PLATFORM, 1.0.3 onboarding)

extension View {
    /// White status bar ink while this screen is on screen, for a screen whose own colour is deep in both appearances.
    /// A screen pushed over it, or a full-screen cover, gives the ink back.
    func lightStatusBar() -> some View {
        modifier(LightStatusBarModifier())
    }
}

private struct LightStatusBarModifier: ViewModifier {
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .background(LightStatusBarAnchor(isActive: isVisible))
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}

/// Tells the overlay window's controller while its screen is visible, as `CallBarStatusBarAnchor` does for the bar.
private struct LightStatusBarAnchor: UIViewRepresentable {
    let isActive: Bool
    
    func makeUIView(context: Context) -> AnchorView {
        AnchorView()
    }
    
    func updateUIView(_ uiView: AnchorView, context: Context) {
        uiView.isActive = isActive
    }
    
    final class AnchorView: UIView {
        var isActive = false {
            didSet { if isActive != oldValue { register() } }
        }
        
        private weak var host: (any LightStatusBarHost)?
        
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            register()
        }
        
        private func register() {
            if host?.lightStatusBarScreen === self {
                host?.lightStatusBarScreen = nil
            }
            host = window?.windowScene?.windows.lazy.compactMap { $0.rootViewController as? any LightStatusBarHost }.first
            if isActive, window != nil {
                host?.lightStatusBarScreen = self
            }
        }
    }
}
