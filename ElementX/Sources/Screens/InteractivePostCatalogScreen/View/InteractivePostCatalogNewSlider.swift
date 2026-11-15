//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (operator, 2026-11-15): every new template under the chips, a card
// each, paged in a loop. It moves on by itself every few seconds while someone can
// watch it (`InteractivePostCatalogNewSliderModel` says when), swipes by hand past
// either end to the card the loop wraps to, and shows where it is in dots under it.
// One new template is the single card, without dots, timer or loop.
//

import Compound
import SwiftUI

struct InteractivePostCatalogNewSlider: View {
    typealias Slot = InteractivePostCatalogNewSliderModel.Slot

    let templates: [SpiralAppTemplate]
    let stills: [String: UIImage]
    let open: (String) -> Void

    @State private var model: InteractivePostCatalogNewSliderModel
    /// The page the pager shows: a real card, or for a moment the copy at the loop's seam.
    @State private var position: Slot?
    @State private var scrollPhase = ScrollPhase.idle
    /// The pager is sliding or fading on its own (the timer, a dot, VoiceOver): the scroll positions it reports
    /// meanwhile are its own, not the person's choice.
    @State private var isMovingByItself = false
    @State private var pagerOpacity = 1.0
    /// The pager's offset has been put on the real card. Until then the card stands still in its place: a first
    /// layout pass shows the copy at offset zero, and iOS 18's snapshots capture that pass.
    @State private var isAligned = false

    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverRunning
    @Environment(\.accessibilityReduceMotion) private var isReduceMotionEnabled
    @Environment(\.scenePhase) private var scenePhase

    init(templates: [SpiralAppTemplate], stills: [String: UIImage], open: @escaping (String) -> Void) {
        self.templates = templates
        self.stills = stills
        self.open = open
        let model = InteractivePostCatalogNewSliderModel(ids: templates.map(\.id),
                                                         autoAdvances: !(ProcessInfo.isRunningTests || ProcessInfo.isXcodePreview))
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isSlider {
                pager
                dots
            } else if let template = templates.first {
                card(template)
                    .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
            }
        }
        .onAppear { model.isAppeared = true }
        .onDisappear { model.isAppeared = false }
        .onScrollVisibilityChange(threshold: 0.5) { isVisible in model.isScrolledIntoView = isVisible }
        .onChange(of: templates.map(\.id)) { _, ids in
            model.update(ids: ids)
            jump(to: model.currentSlot)
        }
        .onChange(of: isVoiceOverRunning, initial: true) { _, isRunning in model.isVoiceOverRunning = isRunning }
        .onChange(of: isReduceMotionEnabled, initial: true) { _, isEnabled in model.isReduceMotionEnabled = isEnabled }
        .onChange(of: scenePhase, initial: true) { _, phase in model.isSceneActive = phase == .active }
        // Cancelled as soon as the schedule changes or the slider leaves the screen: nothing runs offscreen.
        .task(id: model.schedule) {
            guard let schedule = model.schedule else { return }
            try? await Task.sleep(for: schedule.delay)
            // Asked again on waking: a finger may have gone down in the same turn, before this task was cancelled.
            guard !Task.isCancelled, model.mayAutoAdvance, let nextID = model.nextID else { return }
            move(to: nextID) { model.timerFired() }
        }
    }

    /// How the next or previous card slides in, by itself, from a dot or from VoiceOver.
    private static let slide = Animation.smooth(duration: 0.6)
    /// How a card further away replaces the one on screen.
    private static let fadeOut = Animation.easeOut(duration: 0.15)
    private static let fadeIn = Animation.easeIn(duration: 0.2)

    private var pager: some View {
        // Every card, unseen, one over the other: the tallest gives the slider its height, at any text size.
        ZStack {
            ForEach(templates) { template in
                card(template)
            }
        }
        .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
        .frame(maxWidth: .infinity)
        .hidden()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay {
            ScrollViewReader { proxy in
                ZStack {
                    if !isAligned, let template = templates.first(where: { $0.id == model.currentID }) {
                        card(template)
                            .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
                    }
                    pages(proxy: proxy)
                        .opacity(isAligned ? 1 : 0)
                }
            }
        }
    }

    private func pages(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(model.slots, id: \.self) { slot in
                    if let template = templates.first(where: { $0.id == slot.templateID }) {
                        // A copy is the same card: a tap on it opens the real post.
                        card(template)
                            .padding(.horizontal, InteractivePostCatalogCardMetrics.screenMargin)
                            .containerRelativeFrame(.horizontal)
                            // VoiceOver reads the card on screen; the dots page to the others.
                            .accessibilityHidden(slot != model.currentSlot)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position, anchor: .leading)
        // Appearing puts the real first card on screen, one page in past the leading copy: a first value of the
        // position itself is never applied. A new width (rotation, iPad multitasking) keeps the page where it was in
        // points, part of a page off, so the page is put back in place.
        .onAppear { align(proxy: proxy) }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in align(proxy: proxy) }
        .scrollClipDisabled() // The cards' shadow reaches past the pager.
        .opacity(pagerOpacity)
        .onScrollPhaseChange { oldPhase, phase in
            scrollPhase = phase
            if phase == .interacting || (oldPhase != .idle && phase == .idle) {
                isMovingByItself = false // A finger takes over, or any move came to rest, whatever phases it took.
            }
            model.setTouching(phase == .interacting || phase == .decelerating, by: .drag)
            if phase == .idle {
                settle()
            }
        }
        .onChange(of: position) {
            // Mid-swipe the dots follow the page; the copy at the seam gives way only once it rests.
            if scrollPhase != .idle, !isMovingByItself, let position {
                _ = model.settle(on: position)
            }
            // A scroll with no phases of its own, such as VoiceOver's page scroll, settles as it lands.
            if scrollPhase == .idle {
                settle()
            }
        }
    }

    /// The system's page dots, in Compound colours. A dot jumps to its card; VoiceOver adjusts them, in a loop.
    private var dots: some View {
        HStack(spacing: 0) {
            ForEach(templates) { template in
                Circle()
                    // The others a faint one of the same, as the system's page dots: quaternary vanished on the Mist.
                    .fill(Color.compound.iconPrimary.opacity(template.id == model.currentID ? 1 : 0.3))
                    .frame(width: 7, height: 7)
                    // Full height and side by side, so every tap on the row lands on a dot.
                    .frame(width: 16, height: 44)
                    .contentShape(.rect)
                    .onTapGesture { show(template.id) }
            }
        }
        // 44 pt to touch, drawn where the 20 pt row was: the overlap above is the card's own bottom padding.
        .padding(.top, -6)
        .padding(.bottom, -12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(UntranslatedL10n.screenInteractiveCatalogNewBadge)
        .accessibilityValue(dotsValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if let nextID = model.nextID { move(to: nextID) { model.showNext() } }
            case .decrement: if let previousID = model.previousID { move(to: previousID) { model.showPrevious() } }
            @unknown default: break
            }
        }
        .accessibilityIdentifier(A11yIdentifiers.interactivePostCatalogScreen.newDots)
    }

    /// «Dice, 2 of 4».
    private var dotsValue: String {
        let title = templates.first { $0.id == model.currentID }?.localizedTitle ?? ""
        return "\(title), \(UntranslatedL10n.screenInteractiveCatalogPagePosition((model.currentIndex ?? 0) + 1, model.ids.count))"
    }

    private func card(_ template: SpiralAppTemplate) -> some View {
        InteractivePostCatalogNewCard(template: template, still: stills[template.id]) { isPressed in
            model.setTouching(isPressed, by: .press)
        } open: {
            open(template.id)
        }
    }

    // MARK: - Moving

    /// A dot chose a card. Its own dot only pauses the slider.
    private func show(_ id: String) {
        guard id != model.currentID else {
            model.show(id)
            return
        }
        move(to: id) { model.show(id) }
    }

    /// Brings a card on screen: the next or previous one slides in, through the copy at the loop's seam; one
    /// further away cross-fades instead of rewinding through every card between, as everything does with Reduce
    /// Motion on. `change` updates the model.
    private func move(to id: String, change: @escaping () -> Void) {
        isMovingByItself = true
        switch model.transition(to: id) {
        case .slide(let slot):
            withAnimation(Self.slide) {
                change()
                position = slot
            } completion: {
                // Normally the scroll's own rest has settled it already.
                if isMovingByItself, scrollPhase == .idle {
                    isMovingByItself = false
                    settle()
                }
            }
        case .fade(let slot):
            withAnimation(Self.fadeOut) { pagerOpacity = 0 } completion: {
                // A finger that took over meanwhile keeps the card it holds.
                if isMovingByItself {
                    change()
                    jump(to: slot)
                }
                withAnimation(Self.fadeIn) { pagerOpacity = 1 } completion: { isMovingByItself = false }
            }
        }
    }

    /// The pager is at rest: the card it shows is the current one, and a copy at the seam gives way, unseen, to the
    /// real card it shows.
    private func settle() {
        guard !isMovingByItself, let position else { return }
        let real = model.settle(on: position)
        if real != position {
            jump(to: real)
        }
    }

    /// The page on screen exactly in place, without animation.
    private func align(proxy: ScrollViewProxy) {
        guard let slot = position ?? model.currentSlot else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(slot, anchor: .leading)
            position = slot
            isAligned = true
        }
    }

    private func jump(to slot: Slot?) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { position = slot }
    }
}
