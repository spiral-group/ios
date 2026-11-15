//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0083 L1c): keeps Spiral's gates running before any real
// screen opts in, so a gate that broke can't pass by having nothing to check.
// Nothing in the app shows it; only its preview is used, by the tests.

/// A stand-in screen for Spiral's gates, built from Compound tokens only.
struct SpiralGatesFixture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Spiral's gates")
                .font(.compound.headingMDBold)
                .foregroundStyle(.compound.textPrimary)

            Text("Contrast and clipping audits, dark and large text snapshots, and the look of iOS 18.")
                .font(.compound.bodyMD)
                .foregroundStyle(.compound.textSecondary)

            // .secondary as recorded. A .primary label is 4.81:1 in dark since decision 306 (3.65:1 on #0A84FF before).
            Button("Continue") { }
                .buttonStyle(.compound(.secondary))
                .padding(.top, 8)
        }
        .padding(16)
        .background(.compound.bgCanvasDefault)
    }
}

/// The fixture as a whole screen, the way most of the reviewer path is laid out: a navigation
/// bar with a text button, and a primary button that is disabled until there is something to send.
struct SpiralGatesFixtureScreen: View {
    /// Adds what the gates must still fail beside what they exempt: faint text in the content, a
    /// glass-prominent confirm in the navigation bar, and in a toolbar white on #0A84FF (3.65:1) and a
    /// status in two colours of text, which the bars' pixels can't read as one. AccessibilityTests
    /// expect each of those to fail.
    var failsContrast = false

    private static let lowContrastBlue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    /// Glass-prominent draws its label white in light and black in dark, and black on #0A84FF passes
    /// (5.70:1). So dark takes ArmTool's blue, where black fails (4.32:1).
    private static let lowContrastProminentTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.compound.bgActionPrimaryRest.resolvedColor(with: traits)
            : UIColor(red: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)
    })

    private static var twoColourStatus: AttributedString {
        var title = AttributedString("Spiral's gates: ")
        title.foregroundColor = .compound.textPrimary
        var subtitle = AttributedString("low contrast")
        subtitle.foregroundColor = .compound.textSecondary
        return title + subtitle
    }

    var body: some View {
        ElementNavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("A navigation bar's text button and a disabled primary button.")
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)

                Button("Continue") { }
                    .buttonStyle(.compound(.primary))
                    .disabled(true)

                if failsContrast {
                    Text("Faint text that must fail")
                        .font(.compound.bodyMD)
                        .foregroundStyle(Color(uiColor: .systemGray5))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.compound.bgCanvasDefault)
            .navigationTitle("Spiral's gates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if failsContrast {
                        // Styled the way ArmTool's confirm is (decision 306), in a blue that fails.
                        Button("Save") { }
                            .backportButtonStyleGlassProminent(tint: Self.lowContrastProminentTint)
                    } else {
                        Button("Done") { }
                    }
                }

                if failsContrast {
                    ToolbarItem(placement: .bottomBar) {
                        // One element: a bar shows each `Text` of a stack, or of a button's label, as its own.
                        Text(Self.twoColourStatus)
                            .font(.compound.bodyMD)
                    }

                    ToolbarItem(placement: .bottomBar) {
                        Button { } label: {
                            Text("Send")
                                .font(.compound.bodyLGSemibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Self.lowContrastBlue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// What contrast triage K (the runner's reading of an element's own pixels) must not rescue: each is under 4.5:1, so
/// Apple's audit fails it and the runner must let the failure stand (Opus review of the harness lane, 2026-11-14).
struct SpiralGatesPixelFixture: View {
    /// About 4:1 on the Mist where it sits (#DFEAFB light, #2649A0 dark).
    private static let mistText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 175 / 255, green: 175 / 255, blue: 175 / 255, alpha: 1)
            : UIColor(red: 113 / 255, green: 113 / 255, blue: 113 / 255, alpha: 1)
    })
    /// White on it is 4.05:1.
    private static let squareButtonFill = Color(red: 126 / 255, green: 126 / 255, blue: 126 / 255)
    /// On white, 3.55:1.
    private static let largeishText = Color(red: 136 / 255, green: 136 / 255, blue: 136 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Small text straight on the Mist's gradient.
            Text("Small text on the Mist")
                .font(.compound.bodyMD)
                .foregroundStyle(Self.mistText)

            // A square button whose label is text, not a glyph: 4.5:1, not a graphic's 3:1.
            Button { } label: {
                Text("OK")
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Self.squareButtonFill)
            }
            .buttonStyle(.plain)

            // 17 pt text with a glyph of its colour mid-line, parentheses and an accented capital, which take its ink past
            // 18 pt text's (the reader measures the middle 70 % of a line): still text, at 4.5:1.
            (Text("Seventeen ") + Text(Image(systemName: "rectangle.portrait.fill")).font(.system(size: 20)) + Text(" (Ї) points"))
                .font(.system(size: 17))
                .accessibilityLabel("Seventeen (Ї) points")
                .foregroundStyle(Self.largeishText)
                .padding(8)
                .background(Color.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chatBackground()
    }
}

// MARK: - Previews

struct SpiralGatesFixture_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        SpiralGatesFixture()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Fixture")

        SpiralGatesFixtureScreen()
            .previewDisplayName("Screen")

        SpiralGatesFixtureScreen(failsContrast: true)
            .previewDisplayName("Low contrast")

        SpiralGatesPixelFixture()
            .previewDisplayName("Pixels can't rescue")
    }
}
