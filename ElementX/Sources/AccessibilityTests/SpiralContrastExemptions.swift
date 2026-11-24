//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import SwiftUI

// AGENT-PLATFORM (Brief 0083): the app's half of Spiral's contrast gate. On iOS 27 the audit
// reports a contrast issue on SwiftUI text without an element, so the test runner can't tell
// where it is. The app can, so it leaves the exempt parts out of a second, contrast-only audit.

/// Leaves out of Spiral's contrast audit what the gate exempts, when the runner asks (`prepareContrastAudit`):
/// - On iOS 26 and later, navigation bars and toolbars, hidden from accessibility. The audit misreads their
///   Liquid Glass: it fails a "Done" whose pixels read 16–21:1, which iOS 18.6 passes. The runner measures
///   their elements from the screen's pixels instead (`SpiralBarContrast.swift`), and fails one the app hid
///   that it didn't see in a bar. Tab bars stay in the audit, and the runner measures them too. A navigation
///   stack's toolbar is no `UIToolbar` there but a container that floats over the whole screen, so the bars
///   are everything a navigation controller adds beside its content.
/// - Inactive controls, which WCAG 1.4.3 exempts, covered up: a SwiftUI element can't be taken out of the
///   accessibility tree from outside SwiftUI (neither `isAccessibilityElement` nor a container's
///   `accessibilityElements` sticks). A control that overlaps another element stays uncovered, so the
///   cover can't hide anything else.
final class SpiralContrastExemptions {
    private var hiddenBars = [(bar: UIView, wasHidden: Bool)]()
    private var covers = [UIView]()

    private static let maximumDepth = 100
    /// Static text in a disabled stack is `notEnabled` too, but it isn't part of a control.
    private static let controlTraits: UIAccessibilityTraits = [.button, .link, .adjustable, .searchField, .toggleButton]

    /// - Returns: The labelled elements of the bars it hid, for the runner to check that it measured each.
    func apply() -> [UITestsSignal.AccessibilityAudit.HiddenElement] {
        var hiddenElements = [UITestsSignal.AccessibilityAudit.HiddenElement]()
        for window in visibleWindows {
            if #available(iOS 26, *) {
                var bars = [UIView]()
                collectBars(in: window, into: &bars)
                if let root = window.rootViewController {
                    collectNavigationChrome(from: root, into: &bars)
                }
                hiddenElements += bars.flatMap(hide)
            }
            // The keyboard's window, which iOS 27 doesn't list among the scene's windows anyway, sits higher.
            if window.windowLevel <= .normal {
                coverInactiveControls(in: window)
            }
        }
        return hiddenElements
    }

    /// The screen frames of the visible scroll views that can't scroll, such as a list under `scrollDisabled`: a row
    /// their edge cuts never scrolls into view, so the runner's contrast triage L leaves it audited.
    func fixedScrollViewFrames() -> [CGRect] {
        var frames = [CGRect]()
        for window in visibleWindows where window.windowLevel <= .normal {
            collectFixedScrollViews(in: window, of: window, into: &frames)
        }
        return frames
    }

    /// Puts the screen back as it was, before the next preview.
    func remove() {
        hiddenBars.forEach { $0.bar.accessibilityElementsHidden = $0.wasHidden }
        covers.forEach { $0.removeFromSuperview() }
        hiddenBars.removeAll()
        covers.removeAll()
    }

    // MARK: - Private

    private var visibleWindows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
    }

    private func collectBars(in view: UIView, into bars: inout [UIView]) {
        if view is UINavigationBar || view is UIToolbar {
            bars.append(view)
        } else {
            for subview in view.subviews {
                collectBars(in: subview, into: &bars)
            }
        }
    }

    private func collectNavigationChrome(from controller: UIViewController, into bars: inout [UIView]) {
        if let navigationController = controller as? UINavigationController,
           let content = navigationController.topViewController?.viewIfLoaded {
            bars += navigationController.view.subviews.filter { !content.isDescendant(of: $0) }
        }
        for child in controller.children {
            collectNavigationChrome(from: child, into: &bars)
        }
        if let presented = controller.presentedViewController, presented.presentingViewController === controller {
            collectNavigationChrome(from: presented, into: &bars)
        }
    }

    private func hide(_ bar: UIView) -> [UITestsSignal.AccessibilityAudit.HiddenElement] {
        guard !hiddenBars.contains(where: { $0.bar === bar }) else { return [] }
        var elements = [NSObject]()
        collectElements(in: bar, into: &elements, depth: 0)
        hiddenBars.append((bar, bar.accessibilityElementsHidden))
        bar.accessibilityElementsHidden = true
        return elements.compactMap { element in
            guard let label = element.accessibilityLabel, !label.isEmpty, !element.accessibilityFrame.isEmpty else { return nil }
            return .init(label: label, frame: element.accessibilityFrame)
        }
    }

    private func coverInactiveControls(in window: UIWindow) {
        var elements = [NSObject]()
        collectElements(in: window, into: &elements, depth: 0)
        let frames = elements.map(\.accessibilityFrame)

        for (index, element) in elements.enumerated() where Self.isInactiveControl(element) {
            let overlapsAnother = frames.indices.contains { other in
                let overlap = frames[other].intersection(frames[index])
                return other != index && overlap.width > 0.5 && overlap.height > 0.5
            }
            if !overlapsAnother {
                cover(frames[index], in: window)
            }
        }
    }

    /// The elements of the accessibility tree the audit sees; an element is a leaf there.
    private func collectElements(in element: NSObject, into elements: inout [NSObject], depth: Int) {
        guard depth < Self.maximumDepth, !element.accessibilityElementsHidden else { return }
        if let view = element as? UIView, view.isHidden { return }

        if element.isAccessibilityElement {
            elements.append(element)
            return
        }

        for child in accessibilityChildren(of: element) {
            collectElements(in: child, into: &elements, depth: depth + 1)
        }
    }

    private func accessibilityChildren(of element: NSObject) -> [NSObject] {
        if let elements = element.accessibilityElements {
            return elements.compactMap { $0 as? NSObject }
        }
        let count = element.accessibilityElementCount()
        if count != NSNotFound, count > 0 {
            return (0..<count).compactMap { element.accessibilityElement(at: $0) as? NSObject }
        }
        guard let view = element as? UIView else { return [] }
        // A modal view hides its siblings from accessibility.
        if let modal = view.subviews.last(where: { $0.accessibilityViewIsModal && !$0.isHidden }) {
            return [modal]
        }
        return view.subviews
    }

    /// A disabled text field has no public control trait (`notEnabled` and a private text-entry bit);
    /// SwiftUI's is a `UITextField`, or a `UITextView` when it grows vertically.
    private static func isInactiveControl(_ element: NSObject) -> Bool {
        let traits = element.accessibilityTraits
        guard traits.contains(.notEnabled) else { return false }
        return !traits.isDisjoint(with: controlTraits) || element is UITextField || element is UITextView
    }

    private func collectFixedScrollViews(in view: UIView, of window: UIWindow, into frames: inout [CGRect]) {
        if let scrollView = view as? UIScrollView, !scrollView.isScrollEnabled, !scrollView.isHidden {
            let frame = window.convert(scrollView.bounds, from: scrollView)
            frames.append(window.windowScene.map { window.convert(frame, to: $0.screen.coordinateSpace) } ?? frame)
        }
        view.subviews.forEach { collectFixedScrollViews(in: $0, of: window, into: &frames) }
    }

    /// - Parameter screenFrame: An `accessibilityFrame`, which is in screen coordinates.
    private func cover(_ screenFrame: CGRect, in window: UIWindow) {
        let frame = window.windowScene.map { window.convert(screenFrame, from: $0.screen.coordinateSpace) } ?? screenFrame
        let view = UIView(frame: frame)
        view.backgroundColor = .systemBackground
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        window.addSubview(view)
        covers.append(view)
    }
}
