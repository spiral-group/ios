//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (operator, 2026-11-15): the catalogue's «New» card is a slider of
// every new template, in the index's `new` order. It moves on by itself, calmly and
// in a loop, and loops by hand too, only while someone can watch it: on screen and scrolled into view, the
// app active, VoiceOver off, Reduce Motion off, and no finger on it. A touch, a swipe
// or a dot pauses it, and it carries on a while after the finger lifts. Never under
// tests or previews, where a slide would land in a snapshot.
//

import SwiftUI

@Observable
final class InteractivePostCatalogNewSliderModel {
    /// How long a card stays before the next one slides in.
    static let interval: Duration = .seconds(5)
    /// How long it waits after the person last touched it.
    static let pauseAfterTouch: Duration = .seconds(10)

    /// When the next card comes. A new value restarts the wait, so it carries a generation as well as the delay.
    struct Schedule: Equatable {
        let delay: Duration
        let generation: Int
    }

    /// A page of the pager. Around the real cards sit a copy of the last before the first and a copy of the first
    /// after the last, so a swipe or a slide past either end shows the card the loop wraps to; once the pager
    /// settles on a copy it moves, unseen, to the real card the copy shows.
    struct Slot: Hashable {
        enum Place: Hashable {
            case leadingCopy
            case real
            case trailingCopy
        }

        let templateID: String
        let place: Place

        static func real(_ templateID: String) -> Slot {
            Slot(templateID: templateID, place: .real)
        }
    }

    /// How the pager reaches a card: the next or previous one slides in, through a copy at the loop's seam;
    /// one further away (a far dot) cross-fades rather than rewinding through every card between.
    enum Transition: Equatable {
        case slide(to: Slot)
        case fade(to: Slot)
    }

    enum Touch: Hashable {
        /// A finger down on the card's button.
        case press
        /// The pager being dragged, or slowing down after a drag.
        case drag
    }

    private(set) var ids: [String]
    private(set) var currentID: String?
    /// False under tests and previews.
    let autoAdvances: Bool

    /// The slider is in the window: appeared and not covered by a pushed page, a thread or a dismissal.
    var isAppeared = false
    /// At least half of it is inside the catalogue's scroll view: the catalogue's stack is eager, so scrolling
    /// it away is no disappearance.
    var isScrolledIntoView = false
    /// The app is in the foreground.
    var isSceneActive = true
    var isVoiceOverRunning = false
    var isReduceMotionEnabled = false

    private var touches = Set<Touch>()
    /// The person touched it since it last moved on by itself: the next wait is the longer pause.
    private var wasTouched = false
    private var generation = 0

    init(ids: [String], autoAdvances: Bool = true) {
        self.ids = ids
        self.autoAdvances = autoAdvances
        currentID = ids.first
    }

    var currentIndex: Int? {
        currentID.flatMap(ids.firstIndex)
    }

    /// One card needs no dots and no timer.
    var isSlider: Bool {
        ids.count > 1
    }

    var mayAutoAdvance: Bool {
        autoAdvances && isSlider && isAppeared && isScrolledIntoView && isSceneActive
            && !isVoiceOverRunning && !isReduceMotionEnabled && touches.isEmpty
    }

    /// The wait before the next card, or nil when nothing may move on its own.
    var schedule: Schedule? {
        guard mayAutoAdvance else { return nil }
        return Schedule(delay: wasTouched ? Self.pauseAfterTouch : Self.interval, generation: generation)
    }

    /// The card the timer brings next: the first after the last.
    var nextID: String? {
        currentIndex.map { ids[($0 + 1) % ids.count] }
    }

    /// The card before: the last before the first.
    var previousID: String? {
        currentIndex.map { ids[($0 + ids.count - 1) % ids.count] }
    }

    /// The pager's pages: the real cards, with the loop's copies around them once there are two or more.
    var slots: [Slot] {
        let reals = ids.map(Slot.real)
        guard isSlider, let first = ids.first, let last = ids.last else { return reals }
        return [Slot(templateID: last, place: .leadingCopy)] + reals + [Slot(templateID: first, place: .trailingCopy)]
    }

    var currentSlot: Slot? {
        currentID.map(Slot.real)
    }

    /// The next card slides in from the trailing side, the previous from the leading side, through the copy at the
    /// seam when the step wraps. Any other card cross-fades, and so does everything with Reduce Motion on.
    func transition(to id: String) -> Transition {
        guard let index = currentIndex, ids.contains(id) else { return .fade(to: .real(id)) }
        let isLast = index == ids.count - 1
        if id == nextID, !isReduceMotionEnabled {
            return .slide(to: isLast ? Slot(templateID: id, place: .trailingCopy) : .real(id))
        }
        if id == previousID, !isReduceMotionEnabled {
            return .slide(to: index == 0 ? Slot(templateID: id, place: .leadingCopy) : .real(id))
        }
        return .fade(to: .real(id))
    }

    /// The pager came to rest on `slot`. The card it shows is the current one — the person's choice when it
    /// wasn't already — and the real slot comes back to move to unseen when the pager rests on a copy.
    func settle(on slot: Slot) -> Slot {
        if slot.templateID != currentID {
            show(slot.templateID)
        }
        return .real(slot.templateID)
    }

    /// The catalogue's new list changed: the card on screen stays when it is still there.
    func update(ids: [String]) {
        guard ids != self.ids else { return }
        self.ids = ids
        if currentID.map(ids.contains) != true {
            currentID = ids.first
        }
        generation += 1
    }

    /// The wait ran out: the next card, the first after the last.
    func timerFired() {
        guard mayAutoAdvance, let nextID else { return }
        currentID = nextID
        wasTouched = false
        generation += 1
    }

    /// The person chose a card: by swiping to it, tapping its dot, or adjusting with VoiceOver.
    func show(_ id: String) {
        guard ids.contains(id) else { return }
        currentID = id
        wasTouched = true
        generation += 1
    }

    /// The next card, the first after the last: VoiceOver's adjustable step, which loops as a swipe does.
    func showNext() {
        guard isSlider, let nextID else { return }
        show(nextID)
    }

    func showPrevious() {
        guard isSlider, let previousID else { return }
        show(previousID)
    }

    func setTouching(_ isTouching: Bool, by touch: Touch) {
        if isTouching {
            touches.insert(touch)
        } else if touches.remove(touch) != nil {
            wasTouched = true
            generation += 1
        }
    }
}
