//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 onboarding, board pick S3): the start screen's App Store stories on the blue. A slide moves on
// every 4 s; a tap on the trailing two thirds goes on, on the leading third goes back, and holding pauses. The
// clock stays still under Reduce Motion, VoiceOver, Switch Control and keyboard focus (WCAG 2.2.2); VoiceOver changes
// the slide by swiping up or down, a keyboard by the arrows. The text box keeps the tallest slide's height, so nothing
// under it moves when the slide changes.
//

import Compound
import SwiftUI

struct AuthenticationStartStories<Header: View>: View {
    /// The height the stories may take on screen; Spark gets what the rest leaves, never less than `minimumSparkSide`.
    let availableHeight: CGFloat
    /// What sits between the bars and the slide: the brand row.
    @ViewBuilder let header: Header

    @State private var index = 0
    /// Whether a finger is on the story; it resets itself when the system cancels the touch.
    @GestureState private var isTouching = false
    @State private var pressStart: Date?
    @State private var isHeld = false
    @State private var storyFrame: CGRect = .zero
    /// The bars with the header, and the slide's text box, measured. Neither depends on Spark, so measuring them can't
    /// feed back into Spark's box (a total measured with Spark in it rounded differently each pass and never settled).
    @State private var headHeight: CGFloat = 0
    @State private var textBoxHeight: CGFloat = 0

    @FocusState private var isKeyboardFocused: Bool
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection

    private static var minimumSparkSide: CGFloat {
        96
    }
    
    init(availableHeight: CGFloat, @ViewBuilder header: () -> Header) {
        self.availableHeight = availableHeight
        self.header = header()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                AuthenticationStartStoryBars(count: AuthenticationStartSlide.all.count,
                                             index: index,
                                             isPaused: isClockStopped) {
                    show(index + 1)
                }
                .padding(.top, CompoundDesignTokens.space2X)
                
                header
                    .padding(.top, CompoundDesignTokens.space5X)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headHeight = $0 }

            story
                .contentShape(Rectangle())
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { storyFrame = $0 }
                // Simultaneous, so a drag that starts on the slide still scrolls the page; the scroll view then cancels
                // this gesture, which is why taps and holds are all it reads.
                .simultaneousGesture(storyGesture)
                .onChange(of: isTouching) {
                    guard !isTouching else { return }
                    isHeld = false
                    // A touch the system cancels never reaches `onEnded`; one that ends normally has run it by then.
                    let start = pressStart
                    Task {
                        if pressStart == start {
                            pressStart = nil
                        }
                    }
                }
                .focusable(interactions: .activate)
                .focused($isKeyboardFocused)
                .onKeyPress(.rightArrow) {
                    show(layoutDirection == .leftToRight ? index + 1 : index - 1)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    show(layoutDirection == .leftToRight ? index - 1 : index + 1)
                    return .handled
                }
                // Last, so the slide's title and subtitle read as one element whatever the modifiers above add.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(UntranslatedL10n.a11yStartSlidesPosition(index + 1, AuthenticationStartSlide.all.count))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: show(index + 1)
                    case .decrement: show(index - 1)
                    @unknown default: break
                    }
                }
        }
    }
    
    /// Moving content stops for whoever can't follow or pause it with a finger.
    private var isClockStopped: Bool {
        isTouching || reduceMotion || isVoiceOverEnabled || isSwitchControlEnabled || isKeyboardFocused || ProcessInfo.isRunningTests
    }

    // MARK: - Story

    private var slide: AuthenticationStartSlide {
        AuthenticationStartSlide.all[index]
    }

    private var story: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
            ZStack(alignment: .topLeading) {
                // Every slide's text, invisible, so the box is as tall as the tallest one in this language and size.
                ForEach(AuthenticationStartSlide.all.indices, id: \.self) { slideIndex in
                    slideText(AuthenticationStartSlide.all[slideIndex])
                        .hidden()
                }
                .accessibilityHidden(true)
                
                slideText(slide)
                    .id(index)
                    .transition(slideTransition)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textBoxHeight = $0 }
            
            // The outgoing and incoming Spark overlap here while the slide changes; side by side in the stack they
            // would push everything under them down for the length of the transition.
            ZStack {
                Image(asset: slide.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: sparkSide, maxHeight: sparkSide)
                    .id(index)
                    .transition(slideTransition)
            }
            .frame(maxWidth: .infinity)
            .frame(height: sparkBoxHeight)
            .scaleEffect(isHeld ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.2), value: isHeld)
            .accessibilityHidden(true)
        }
        .padding(.top, CompoundDesignTokens.space6X)
    }
    
    private func slideText(_ slide: AuthenticationStartSlide) -> some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
            Text(slide.title)
                .font(.compound.headingXLBold)
                .foregroundStyle(.white)
            
            Text(slide.subtitle)
                .font(.compound.bodyLG)
                .foregroundStyle(.white.opacity(0.9))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var slideTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                              removal: .opacity.combined(with: .offset(x: -24)))
    }
    
    /// One gesture for both: a short press is a tap, by its side; a longer one holds the story still until it lifts.
    /// Global coordinates, so the leading third is the right one in a right-to-left language.
    private var storyGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($isTouching) { _, isTouching, _ in
                isTouching = true
            }
            .onChanged { _ in
                guard pressStart == nil else { return }
                let start = Date.now
                pressStart = start
                Task {
                    try? await Task.sleep(for: .seconds(0.2))
                    if pressStart == start, isTouching {
                        isHeld = true
                    }
                }
            }
            .onEnded { value in
                let wasTap = pressStart.map { Date.now.timeIntervalSince($0) < 0.25 } ?? true
                pressStart = nil
                guard wasTap, abs(value.translation.width) < 20, abs(value.translation.height) < 20 else { return }
                // The leading third goes back, as in the stories people know.
                let x = value.location.x
                let isLeadingThird = layoutDirection == .leftToRight ? x < storyFrame.minX + storyFrame.width / 3 : x > storyFrame.maxX - storyFrame.width / 3
                show(isLeadingThird ? index - 1 : index + 1)
            }
    }

    /// Spark's largest side; with very large text it gives more room to the words.
    private var sparkSide: CGFloat {
        dynamicTypeSize > .xxLarge ? 160 : 320
    }
    
    /// What the page leaves for Spark, so the buttons sit at the screen's bottom; at the minimum the page scrolls. The
    /// text keeps the tallest slide's height, so this doesn't change from slide to slide.
    private var sparkBoxHeight: CGFloat {
        let chromeHeight = headHeight + CompoundDesignTokens.space6X + textBoxHeight + CompoundDesignTokens.space3X
        return max(Self.minimumSparkSide, availableHeight - chromeHeight)
    }

    private func show(_ newIndex: Int) {
        let count = AuthenticationStartSlide.all.count
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0)) {
            index = (newIndex + count) % count
        }
    }
}

// MARK: - Slides

struct AuthenticationStartSlide {
    let title: String
    let subtitle: String
    let image: ImageAsset

    static var all: [AuthenticationStartSlide] {
        [.init(title: UntranslatedL10n.screenStartSlidePrivacyTitle,
               subtitle: UntranslatedL10n.screenStartSlidePrivacySubtitle,
               image: Asset.Images.sparkShield),
         .init(title: UntranslatedL10n.screenStartSlideCallsTitle,
               subtitle: UntranslatedL10n.screenStartSlideCallsSubtitle,
               image: Asset.Images.sparkTranslate),
         .init(title: UntranslatedL10n.screenStartSlideAssistantTitle,
               subtitle: UntranslatedL10n.screenStartSlideAssistantSubtitle,
               image: Asset.Images.sparkPoint),
         .init(title: UntranslatedL10n.screenStartSlideGamesTitle,
               subtitle: UntranslatedL10n.screenStartSlideGamesSubtitle,
               image: Asset.Images.sparkJoy)]
    }
}

// MARK: - Bars

/// The stories' bars: past slides full, the current one filling, the rest faint. The clock lives here, so its ticks
/// redraw the bars alone.
private struct AuthenticationStartStoryBars: View {
    let count: Int
    let index: Int
    let isPaused: Bool
    let onFinish: () -> Void

    @State private var progress = 0.0
    /// The clock's task holds a copy of this view, so it reads the pause through state rather than `isPaused`.
    @State private var isClockPaused = false

    private static let slideDuration = 4.0
    private static let tick = 0.05

    var body: some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            ForEach(0..<count, id: \.self) { bar in
                Capsule()
                    .fill(.white.opacity(0.32))
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(.white)
                                .frame(width: geometry.size.width * fill(for: bar))
                        }
                    }
                    .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
        .onChange(of: isPaused, initial: true) { isClockPaused = isPaused }
        .task(id: index) { await runClock() }
    }

    private func fill(for bar: Int) -> Double {
        if bar < index {
            1
        } else if bar == index {
            progress
        } else {
            0
        }
    }

    private func runClock() async {
        progress = 0
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.tick))
            guard !Task.isCancelled, !isClockPaused else { continue }
            progress = min(1, progress + Self.tick / Self.slideDuration)
            if progress >= 1 {
                onFinish()
                return
            }
        }
    }
}
