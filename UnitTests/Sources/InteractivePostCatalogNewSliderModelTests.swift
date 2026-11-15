//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (operator, 2026-11-15): the catalogue's «New» slider — its order, one card
// or none, when it moves on by itself, and when it must not.
//

@testable import Spiral
import Testing

struct InteractivePostCatalogNewSliderModelTests {
    typealias Slot = InteractivePostCatalogNewSliderModel.Slot

    @Test
    func theSliderStartsOnTheFirstNewPostAndLoopsInTheCataloguesOrder() {
        let model = watched(["fishing", "snowman", "backgammon"])
        #expect(model.currentID == "fishing")
        #expect(model.isSlider)

        model.timerFired()
        #expect(model.currentID == "snowman")
        model.timerFired()
        #expect(model.currentID == "backgammon")
        model.timerFired()
        #expect(model.currentID == "fishing", "the first after the last")
    }

    @Test
    func oneNewPostIsACardWithoutDotsOrTimer() {
        let model = watched(["fishing"])
        #expect(!model.isSlider)
        #expect(model.schedule == nil)

        model.timerFired()
        #expect(model.currentID == "fishing")
    }

    @Test
    func nothingNewIsNothing() {
        let model = watched([])
        #expect(model.currentID == nil)
        #expect(!model.isSlider)
        #expect(model.schedule == nil)

        model.timerFired()
        #expect(model.currentID == nil)
    }

    @Test
    func itWaitsTheCalmIntervalWhileSomeoneWatches() throws {
        let model = watched(["a", "b"])
        let schedule = try #require(model.schedule)
        #expect(schedule.delay == InteractivePostCatalogNewSliderModel.interval)

        model.timerFired()
        let next = try #require(model.schedule)
        #expect(next.delay == InteractivePostCatalogNewSliderModel.interval)
        #expect(next != schedule, "each card restarts the wait")
    }

    @Test
    func aSwipeOrADotPausesItForLongerThenItCarriesOn() {
        let model = watched(["a", "b", "c"])

        model.show("c")
        #expect(model.currentID == "c")
        #expect(model.schedule?.delay == InteractivePostCatalogNewSliderModel.pauseAfterTouch)

        model.timerFired()
        #expect(model.currentID == "a")
        #expect(model.schedule?.delay == InteractivePostCatalogNewSliderModel.interval, "the pause is once")

        model.show("gone")
        #expect(model.currentID == "a", "an id it doesn't hold changes nothing")
    }

    @Test
    func aFingerOnItHoldsItStillUntilItLifts() {
        let model = watched(["a", "b"])

        model.setTouching(true, by: .press)
        #expect(model.schedule == nil)
        model.timerFired()
        #expect(model.currentID == "a", "a late timer moves nothing under a finger")

        // A press that turns into a drag: still held while the drag goes on.
        model.setTouching(true, by: .drag)
        model.setTouching(false, by: .press)
        #expect(model.schedule == nil)

        model.setTouching(false, by: .drag)
        #expect(model.schedule?.delay == InteractivePostCatalogNewSliderModel.pauseAfterTouch)
    }

    @Test
    func voiceOverStopsIt() {
        let model = watched(["a", "b"])
        model.isVoiceOverRunning = true
        #expect(model.schedule == nil)

        model.timerFired()
        #expect(model.currentID == "a")

        model.showNext()
        #expect(model.currentID == "b", "VoiceOver pages by hand")
        model.showNext()
        #expect(model.currentID == "a", "and loops past the last, as a swipe does")
        model.showPrevious()
        #expect(model.currentID == "b", "and back past the first")
    }

    @Test
    func reduceMotionStopsIt() {
        let model = watched(["a", "b"])
        model.isReduceMotionEnabled = true
        #expect(model.schedule == nil)

        model.timerFired()
        #expect(model.currentID == "a")
    }

    @Test
    func theTimerStopsOffscreenAndComesBackWithTheScreen() {
        let model = InteractivePostCatalogNewSliderModel(ids: ["a", "b"])
        model.isScrolledIntoView = true
        #expect(model.schedule == nil, "nothing runs before the slider is on screen")

        model.isAppeared = true
        #expect(model.schedule != nil)

        // A post page pushed over the catalogue, a thread, or the sheet dismissed.
        model.isAppeared = false
        #expect(model.schedule == nil)
        model.timerFired()
        #expect(model.currentID == "a", "a late timer moves nothing offscreen")

        model.isAppeared = true
        model.isSceneActive = false
        #expect(model.schedule == nil, "nor in the background")

        model.isSceneActive = true
        #expect(model.schedule != nil)
    }

    @Test
    func scrollingItOutOfViewStopsIt() {
        let model = watched(["a", "b"])
        model.isScrolledIntoView = false
        #expect(model.schedule == nil, "the catalogue's stack is eager: scrolled away is no disappearance")
        model.timerFired()
        #expect(model.currentID == "a")

        model.isScrolledIntoView = true
        #expect(model.schedule != nil)
    }

    @Test
    func underTestsAndPreviewsItNeverMovesByItself() {
        let model = InteractivePostCatalogNewSliderModel(ids: ["a", "b"], autoAdvances: false)
        model.isAppeared = true
        model.isScrolledIntoView = true
        #expect(model.isSlider)
        #expect(model.schedule == nil)

        model.timerFired()
        #expect(model.currentID == "a")
        model.show("b")
        #expect(model.currentID == "b", "a person still pages it")
    }

    @Test
    func thePagerHasACopyOfTheLastBeforeTheFirstAndOfTheFirstAfterTheLast() {
        let model = watched(["a", "b", "c"])
        #expect(model.slots == [Slot(templateID: "c", place: .leadingCopy), .real("a"), .real("b"), .real("c"),
                                Slot(templateID: "a", place: .trailingCopy)])
        #expect(model.currentSlot == .real("a"), "it starts on the real first card, not the copy")

        #expect(watched(["a"]).slots == [.real("a")], "one card doesn't loop")
        #expect(watched([]).slots.isEmpty)
    }

    @Test
    func theNextAndPreviousCardsSlideAndOneFurtherAwayFades() {
        let model = watched(["a", "b", "c", "d"])
        #expect(model.transition(to: "b") == .slide(to: .real("b")))
        #expect(model.transition(to: "d") == .slide(to: Slot(templateID: "d", place: .leadingCopy)),
                "back from the first: the copy of the last before it")
        #expect(model.transition(to: "c") == .fade(to: .real("c")), "a far dot doesn't rewind through the cards between")

        model.isReduceMotionEnabled = true
        #expect(model.transition(to: "b") == .fade(to: .real("b")), "Reduce Motion fades everything")
    }

    @Test
    func theTimerWrapsForwardThroughTheCopyOfTheFirst() {
        let model = watched(["a", "b", "c"])
        model.show("c")
        model.timerFired() // The pause after the person's choice is the view's to wait out.
        #expect(model.currentID == "a")

        model.show("c")
        #expect(model.nextID == "a")
        #expect(model.transition(to: "a") == .slide(to: Slot(templateID: "a", place: .trailingCopy)),
                "one card forward into the copy, no rewind and no fade")
    }

    @Test
    func aSwipePastTheLastShowsTheFirstAndMovesToItUnseen() {
        let model = watched(["a", "b", "c"])
        model.show("c")
        model.timerFired()
        model.show("c")

        let real = model.settle(on: Slot(templateID: "a", place: .trailingCopy))
        #expect(real == .real("a"), "the pager moves from the copy to the real first card")
        #expect(model.currentID == "a", "the dots name the real card")
        #expect(model.schedule?.delay == InteractivePostCatalogNewSliderModel.pauseAfterTouch, "a swipe pauses it")
    }

    @Test
    func aSwipeBackFromTheFirstShowsTheLastAndMovesToItUnseen() {
        let model = watched(["a", "b", "c"])
        let real = model.settle(on: Slot(templateID: "c", place: .leadingCopy))
        #expect(real == .real("c"))
        #expect(model.currentID == "c")
    }

    @Test
    func thePagersOwnSlideIntoTheCopyComesToRestWithoutCountingAsATouch() {
        let model = watched(["a", "b"])
        model.timerFired()
        model.timerFired()
        #expect(model.currentID == "a", "the timer wrapped and set the real card first")

        let real = model.settle(on: Slot(templateID: "a", place: .trailingCopy))
        #expect(real == .real("a"))
        #expect(model.schedule?.delay == InteractivePostCatalogNewSliderModel.interval, "its own wrap is no pause")
    }

    @Test
    func twoCardsSlideForwardFirst() {
        let model = watched(["a", "b"])
        #expect(model.transition(to: "b") == .slide(to: .real("b")))
        model.show("b")
        #expect(model.transition(to: "a") == .slide(to: Slot(templateID: "a", place: .trailingCopy)))
    }

    @Test
    func aChangedNewListKeepsTheCardOnScreenWhenItIsStillThere() {
        let model = watched(["a", "b", "c"])
        model.show("b")

        model.update(ids: ["c", "b"])
        #expect(model.currentID == "b")

        model.update(ids: ["c"])
        #expect(model.currentID == "c", "gone: the first")
        #expect(!model.isSlider)
    }

    // MARK: - Helpers

    /// A slider on screen and scrolled into view, in the foreground, VoiceOver and Reduce Motion off.
    private func watched(_ ids: [String]) -> InteractivePostCatalogNewSliderModel {
        let model = InteractivePostCatalogNewSliderModel(ids: ids)
        model.isAppeared = true
        model.isScrolledIntoView = true
        return model
    }
}
