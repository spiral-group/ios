//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import SpiralComponents
import SwiftUI
import Testing

// AGENT-PLATFORM (Brief 0083 L1c): Spiral's snapshot gates for the previews that
// conform to `SpiralGatedPreview`. Their tests are generated into
// GeneratedSpiralGatedPreviewTests.swift (Tools/Sourcery/SpiralGatedPreviewTests.stencil),
// one per preview, named like upstream's test of the same preview, so the
// references sit next to upstream's: `fooScreen.Content-iPhone-en-GB-dark.png`.

/// Every state of a `SpiralGatedPreview`, in dark, at AX3 and right to left on iOS 27, where
/// upstream's suite has the light one. On iOS 18.6, the pre-glass lane, in all four.
///
/// A test renders every state three times over on two devices, and a render through the key window settles over up to
/// `SpiralGlassRendering.settlingRenders` renders, so the larger previews outrun the test plan's 60 s default: in the
/// 1.0.2 final pass `approvalDetailScreen`, `nativeCallScreen`, `roomDetailsScreen` and the pre-glass `roomScreen` were
/// stopped at 60 s, and the runner restarted the app without recording their last states.
@Suite(.timeLimit(.minutes(5)))
struct SpiralGatedPreviewTests {
    private let previewTests = PreviewTests(lanes: [.current, .preGlass])

    func assertSnapshots(matching preview: _Preview,
                         step: Int,
                         testName: String = #function,
                         sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await previewTests.assertSnapshots(matching: preview,
                                               step: step,
                                               variants: previewTests.lane.gatedVariants,
                                               testName: testName,
                                               sourceLocation: sourceLocation)
    }
}

/// Where a PreviewTests run renders, and what it compares with. The OS picks it.
enum SnapshotLane {
    /// The OS upstream pins, `PreviewTests.requiredOSVersion`. References in `__Snapshots__/PreviewTests`.
    case current
    /// iOS 18.6, without Liquid Glass, for the look Spiral keeps on iOS 18.5 to 25.
    /// Only `SpiralGatedPreviewTests` run here (`run-preview-tests.sh --pre-glass`),
    /// against their own references in `__Snapshots__/PreviewTests-preGlass`.
    case preGlass

    static let preGlassOSVersion = (major: 18, minor: 6)

    /// `nil` when no lane runs on this OS.
    init?(osVersion: OperatingSystemVersion, requiredOSVersion: (major: Int, minor: Int)) {
        let version = (major: osVersion.majorVersion, minor: osVersion.minorVersion)
        if version == requiredOSVersion {
            self = .current
        } else if version == Self.preGlassOSVersion {
            self = .preGlass
        } else {
            return nil
        }
    }

    /// What a gated preview renders. On the current lane upstream's suite has the light one.
    var gatedVariants: [SnapshotVariant] {
        switch self {
        case .current: [.dark, .accessibility3, .rightToLeft]
        case .preGlass: [.standard, .dark, .accessibility3, .rightToLeft]
        }
    }

    /// Whether a gated preview renders through the key window, where Liquid Glass shows (`SpiralGlassRendering`).
    /// iOS 18.6 has no glass to draw, so the pre-glass lane keeps its renders as they were.
    var drawsGlass: Bool {
        switch self {
        case .current: true
        case .preGlass: false
        }
    }

    /// `nil` keeps swift-snapshot-testing's default, the folder named after PreviewTests.swift.
    var snapshotDirectory: String? {
        switch self {
        case .current: nil
        case .preGlass: URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent().appendingPathComponent("__Snapshots__/PreviewTests-preGlass").path
        }
    }
}

/// Liquid Glass in snapshots (Brief 0083 end stage, operator 2026-11-14).
///
/// swift-snapshot-testing draws a view with `layer.render(in:)` by default, which draws no Liquid Glass, no scroll edge
/// effect and no other backdrop: on iOS 27 the bars' buttons and capsules came out bare, light bar buttons vanished on
/// light content and dark bar labels had no glass behind them. A render through the app's key window
/// (`drawViewHierarchy(in:afterScreenUpdates:)`, the library's `drawHierarchyInKeyWindow`) goes through the render
/// server and draws them. So the previews that conform to `SpiralGatedPreview` render that way on iOS 27, in
/// upstream's suite (their light references) and in `SpiralGatedPreviewTests` (dark, AX3, right to left). Upstream's
/// other previews keep `layer.render(in:)`, so their references don't move.
///
/// The render server settles glass and the scroll edge effect over a few frames, and what the previous test drew in the
/// key window shows in the first renders: run in another order, 18 of 112 renders of RoomScreen came out with or without
/// the header's glass, or a few points apart. So a render is repeated until two in a row are the same (at most
/// `settlingRenders`) before the compared one. Settled, two runs in different orders gave 71 of 72 RoomScreen renders
/// byte-identical and one with one pixel one level apart (2026-11-14). These renders compare at a perceptual precision of
/// 0.98 (a pixel matches within a Delta E of 2, under what an eye tells apart), with every pixel still required to match.
/// A preview that asks for less keeps its own.
enum SpiralGlassRendering {
    static let perceptualPrecision: Float = 0.98
    /// At most this many renders before the compared one, until two in a row are the same.
    static let settlingRenders = 6

    static func drawsGlass(suite: String) -> Bool {
        SpiralGatedPreviewTests.suites.contains(suite)
    }
}

/// One way to render a snapshot.
enum SnapshotVariant {
    /// Upstream's: the simulator's appearance, which is light, at the default text size.
    case standard
    case dark
    /// Dynamic Type's `accessibility3`, the size Spiral's screens are checked at.
    case accessibility3
    /// Right to left with English text, so a layout that doesn't mirror shows (decision 302).
    case rightToLeft

    var nameSuffix: String {
        switch self {
        case .standard: ""
        case .dark: "-dark"
        case .accessibility3: "-AX3"
        case .rightToLeft: "-rtl"
        }
    }

    func traits(_ traits: UITraitCollection) -> UITraitCollection {
        switch self {
        case .standard: traits
        case .dark: traits.modifyingTraits { $0.userInterfaceStyle = .dark }
        case .accessibility3: traits.modifyingTraits { $0.preferredContentSizeCategory = .accessibilityExtraLarge }
        case .rightToLeft: traits.modifyingTraits { $0.layoutDirection = .rightToLeft }
        }
    }

    /// The text size UIKit's text styles resolve at while this variant renders, `nil` to leave the app's.
    var uiKitContentSizeCategory: UIContentSizeCategory? {
        switch self {
        case .accessibility3: .accessibilityExtraLarge
        case .standard, .dark, .rightToLeft: nil
        }
    }

    /// Runs `body`, the variant's renders, with UIKit's own text size at the variant's (F2).
    ///
    /// `UIFont.preferredFont(forTextStyle:)` ignores the traits a snapshot sets, `UITraitCollection.current` and a
    /// scene's trait overrides: it reads the system's text size preference, `UIContentSizeCategoryPreference.system` in
    /// UIKit (iOS 27). So a message body (`FormattedBodyText`), a quote and the space kept for the time stayed at the
    /// default size in AX3 references while SwiftUI text grew. While the variant renders, that preference holds the
    /// variant's size, as the device's setting would, and it is put back after; this writes no defaults and posts no
    /// notification. (UIKit's `overrideSystemWithPreference:` didn't reach `preferredFont` before the render.)
    ///
    /// Not covered: sizes a builder fixes when an item is built, such as `AttributedStringBuilder`'s bold, italic,
    /// heading and code runs. A preview builds its items once, before any variant renders, so those runs keep the
    /// default size at AX3.
    func withUIKitTextSize<Result>(_ body: () -> Result) -> Result {
        guard let category = uiKitContentSizeCategory else { return body() }

        let key = "preferredContentSizeCategory"
        guard let preferenceClass = NSClassFromString("UIContentSizeCategoryPreference") as? NSObject.Type,
              preferenceClass.responds(to: NSSelectorFromString("system")),
              let system = preferenceClass.perform(NSSelectorFromString("system"))?.takeUnretainedValue() as? NSObject,
              system.responds(to: NSSelectorFromString("setPreferredContentSizeCategory:")),
              let original = system.value(forKey: key) as? String else {
            Issue.record("UIKit's text size preference isn't where it was on iOS 27: its text styles would render at the default size")
            return body()
        }
        system.setValue(category.rawValue, forKey: key)
        defer { system.setValue(original, forKey: key) }

        // The override must reach `preferredFont`, or the variant would be recorded at the default size again.
        let expected = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: category)).pointSize
        let actual = UIFont.preferredFont(forTextStyle: .body).pointSize
        if actual != expected {
            Issue.record("UIKit's body text is \(actual) pt under the \(category.rawValue) override, not \(expected) pt")
        }
        return body()
    }

    /// Sets the environment as well: a size-to-fit snapshot measures its view before the traits reach it. Every
    /// variant also takes what the app sets at its window's root, which a snapshot's own window doesn't inherit:
    /// under tests, a still preloader (`Application`).
    func content(_ content: AnyView) -> AnyView {
        let content = AnyView(content.environment(\.spiralPreloaderShimmers, !ProcessInfo.isRunningTests))
        return switch self {
        case .standard: content
        case .dark: AnyView(content.environment(\.colorScheme, .dark))
        case .accessibility3: AnyView(content.environment(\.dynamicTypeSize, .accessibility3))
        case .rightToLeft: AnyView(content.environment(\.layoutDirection, .rightToLeft))
        }
    }
}
