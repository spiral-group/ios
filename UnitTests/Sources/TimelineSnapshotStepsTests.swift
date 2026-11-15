//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 items 16 and 17): how an animated update lands, and how a long jump goes.
//

@testable import Spiral
import Testing

struct TimelineSnapshotStepsTests {
    private func steps(_ current: [String], _ new: [String]) -> TimelineSnapshotSteps<String> {
        TimelineSnapshotSteps(current: current, new: new) { $0.hasPrefix("virtual") }
    }
    
    @Test
    func aRowArrivingAtTheEndIsAllThereIsToAnimate() {
        let steps = steps(["b", "a"], ["c", "b", "a"])
        
        #expect(steps.inPlace.isEmpty)
        #expect(steps.leaving.isEmpty)
    }
    
    @Test
    func aDateArrivingWithItsRowSlidesInWithIt() {
        let steps = steps(["b", "a"], ["c", "virtual-date", "b", "a"])
        
        #expect(steps.inPlace.isEmpty)
    }
    
    @Test
    func theNewDividerLeavesInPlaceBeforeYourMessageSlidesIn() {
        let steps = steps(["b", "virtual-new", "a"], ["mine", "b", "a"])
        
        #expect(steps.inPlace == [["b", "a"]])
        #expect(steps.leaving == ["virtual-new"])
    }
    
    @Test
    func aRowArrivingAmongOthersGoesInPlace() {
        let steps = steps(["c", "a"], ["d", "c", "virtual-date", "a"])
        
        #expect(steps.inPlace == [["c", "virtual-date", "a"]])
        #expect(steps.leaving.isEmpty)
    }
    
    @Test
    func aDividerThatMovesGoesAndComesBackRatherThanSlideOverTheRows() {
        let steps = steps(["c", "b", "virtual-new", "a"], ["d", "virtual-new", "c", "b", "a"])
        
        #expect(steps.inPlace == [["c", "b", "a"], ["virtual-new", "c", "b", "a"]])
        #expect(steps.leaving == ["virtual-new"])
    }
    
    @Test
    func aDividerLeftWhereItWasStays() {
        let steps = steps(["b", "virtual-new", "a"], ["c", "b", "virtual-new", "a"])
        
        #expect(steps.inPlace.isEmpty)
        #expect(steps.leaving.isEmpty)
    }
    
    @Test
    func theNewestRowLeavingClosesTheGapInPlace() {
        let steps = steps(["c", "b", "a"], ["b", "a"])
        
        #expect(steps.inPlace == [["b", "a"]])
        #expect(steps.leaving == ["c"])
    }
}

struct TimelineJumpTests {
    @Test(arguments: [(target: 0, visible: 3...12), (target: 30, visible: 3...12), (target: 36, visible: 3...12), (target: 0, visible: 24...30)])
    func aShortScrollStaysOne(target: Int, visible: ClosedRange<Int>) {
        #expect(TimelineJump.cutRow(from: visible, to: target) == nil)
    }
    
    @Test
    func aLongJumpTowardsTheOldestCutsToJustShortOfIt() {
        #expect(TimelineJump.cutRow(from: 0...10, to: 400) == 392)
    }
    
    @Test
    func aLongJumpTowardsTheNewestCutsToJustShortOfIt() {
        #expect(TimelineJump.cutRow(from: 390...400, to: 0) == 8)
    }
}
