//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import SwiftUI
import Testing

/// The group video's stage follows the conversation, but only a sustained turn moves it (question 383).
struct NativeCallGroupFocusTests {
    private let people = ["@mira:example.org", "@oleh:example.org", "@iryna:example.org"]

    @Test
    func theFirstPersonTakesTheStageBeforeAnyoneSpeaks() {
        var focus = NativeCallGroupFocus()
        focus.update(at: 0, candidates: people, speaking: [])
        #expect(focus.focused == people[0])
    }

    @Test
    func aShortSoundDoesNotMoveTheStage() {
        var focus = NativeCallGroupFocus()
        focus.update(at: 0, candidates: people, speaking: [])
        focus.update(at: 1, candidates: people, speaking: [people[1]])
        focus.update(at: 1.6, candidates: people, speaking: [])
        focus.update(at: 3, candidates: people, speaking: [])
        #expect(focus.focused == people[0], "a 0.6 s sound is not a turn")
    }

    @Test
    func aSustainedTurnMovesTheStage() {
        var focus = NativeCallGroupFocus()
        focus.update(at: 0, candidates: people, speaking: [])
        focus.update(at: 1, candidates: people, speaking: [people[2]])
        #expect(focus.nextDecision(after: 1) == 2, "the stage asks to be looked at again when the turn is sustained")
        focus.update(at: 1.9, candidates: people, speaking: [people[2]])
        #expect(focus.focused == people[0])
        focus.update(at: 2, candidates: people, speaking: [people[2]])
        #expect(focus.focused == people[2])
    }

    @Test
    func theStageStaysWhileTheFocusedPersonSpeaks() {
        var focus = NativeCallGroupFocus()
        focus.update(at: 0, candidates: people, speaking: [people[0]])
        focus.update(at: 0.5, candidates: people, speaking: [people[0], people[1]])
        focus.update(at: 3, candidates: people, speaking: [people[0], people[1]])
        #expect(focus.focused == people[0], "talking over the focused person doesn't take the stage")

        focus.update(at: 3.5, candidates: people, speaking: [people[1]])
        #expect(focus.focused == people[0], "they have only just stopped")
        focus.update(at: 4, candidates: people, speaking: [people[1]])
        #expect(focus.focused == people[1], "quiet for a moment, the one who held the floor longest takes it")
    }

    @Test
    func aBreathDoesNotHandTheStageOver() {
        var focus = NativeCallGroupFocus()
        focus.update(at: 0, candidates: people, speaking: [people[0]])
        focus.update(at: 1, candidates: people, speaking: [people[0], people[1]])
        focus.update(at: 3, candidates: people, speaking: [people[1]])
        #expect(focus.nextDecision(after: 3) == 3.5, "the stage looks again once the pause is more than a breath")
        focus.update(at: 3.4, candidates: people, speaking: [people[1]])
        focus.update(at: 3.45, candidates: people, speaking: [people[0], people[1]])
        focus.update(at: 4, candidates: people, speaking: [people[0], people[1]])
        #expect(focus.focused == people[0])
    }

    @Test
    func aVoiceThatNeverStopsCannotHoldTheStage() {
        var focus = NativeCallGroupFocus()
        // A television by people[0]'s open microphone: "speaking" from the start, never a break.
        focus.update(at: 0, candidates: people, speaking: [people[0]])
        focus.update(at: 5, candidates: people, speaking: [people[0], people[1]])
        #expect(focus.nextDecision(after: 5) == NativeCallGroupFocus.floorHeldTooLong)
        focus.update(at: 7.9, candidates: people, speaking: [people[0], people[1]])
        #expect(focus.focused == people[0], "talking over someone isn't taking the stage while their turn is plausible")
        focus.update(at: 8, candidates: people, speaking: [people[0], people[1]])
        #expect(focus.focused == people[1], "a voice that never stops loses the stage to someone really speaking")

        focus.update(at: 9, candidates: people, speaking: [people[0]])
        focus.update(at: 10, candidates: people, speaking: [people[0]])
        #expect(focus.focused == people[1], "and its unbroken run can't take it back")

        focus.update(at: 10.5, candidates: people, speaking: [])
        focus.update(at: 11, candidates: people, speaking: [people[0]])
        focus.update(at: 12, candidates: people, speaking: [people[0]])
        #expect(focus.focused == people[0], "after a real break it is a speaker like anyone else")
    }

    @Test
    func someoneLeavingHandsTheStageOn() {
        var focus = NativeCallGroupFocus()
        focus.update(at: 0, candidates: people, speaking: [])
        focus.update(at: 1, candidates: Array(people.dropFirst()), speaking: [])
        #expect(focus.focused == people[1])
        focus.update(at: 2, candidates: [], speaking: [])
        #expect(focus.focused == nil)
    }
}

/// The group strip shows whole tiles only: as many as fit at their smallest length, at least one (question 383).
struct NativeCallTileStripTests {
    private typealias Strip = NativeCallTileStrip<NativeCallParticipant, EmptyView>

    @Test
    func aUsualPhoneFitsFourFilmstripTiles() {
        // 393 pt wide less the stage's 12 pt margins, tiles of at least 80 pt with 8 pt between.
        #expect(Strip.tilesPerRow(length: 369, minimumTileLength: 80, spacing: 8) == 4)
    }

    @Test
    func largerTextFitsFewerWholeTiles() {
        #expect(Strip.tilesPerRow(length: 369, minimumTileLength: 120, spacing: 8) == 2)
        #expect(Strip.tilesPerRow(length: 369, minimumTileLength: 400, spacing: 8) == 1, "one whole tile, never none")
        #expect(Strip.tilesPerRow(length: 0, minimumTileLength: 80, spacing: 8) == 0, "nothing before the strip is measured")
    }

    /// Whole-tile pages: one swipe is one page, one dot a page.
    @Test
    func theTilesComeInWholePages() {
        #expect(Strip.pageCount(items: 11, perPage: 4) == 3, "4, 4 and the last 3")
        #expect(Strip.pageCount(items: 4, perPage: 4) == 1)
        #expect(Strip.pageCount(items: 5, perPage: 4) == 2)
        #expect(Strip.pageCount(items: 3, perPage: 0) == 0, "nothing before the strip is measured")
    }
}

/// The Aura edge's outline, sampled once per size.
struct NativeCallRoundedPerimeterTests {
    @Test
    func theSamplesWalkTheOutlineAndCloseIt() {
        let perimeter = NativeCallRoundedPerimeter(rect: CGRect(x: 0, y: 0, width: 100, height: 60), radius: 10)
        let samples = perimeter.samples(count: 200)

        #expect(samples.count == 201)
        #expect(samples[0].point == CGPoint(x: 10, y: 0))
        #expect(abs(samples[200].point.x - samples[0].point.x) < 0.001 && abs(samples[200].point.y - samples[0].point.y) < 0.001)
        #expect(samples.allSatisfy { $0.point.x >= -0.001 && $0.point.x <= 100.001 && $0.point.y >= -0.001 && $0.point.y <= 60.001 })
    }
}

/// The corner tile snaps to the corner its drag was headed for; trailing is the right in left to right and the left in
/// right to left (question 383).
struct NativeCallCornerTileTests {
    private let size = CGSize(width: 378, height: 500)
    private let tile = CGSize(width: 104, height: 156)

    @Test
    func aShortDragStaysInItsCorner() {
        #expect(corner(from: .topTrailing, by: CGSize(width: -40, height: 30)) == .topTrailing)
        #expect(corner(from: .topTrailing, by: .zero, isRightToLeft: true) == .topTrailing)
    }

    @Test
    func aDragAcrossTheMiddleLandsInTheNearestCorner() {
        #expect(corner(from: .topTrailing, by: CGSize(width: -250, height: 0)) == .topLeading)
        #expect(corner(from: .topTrailing, by: CGSize(width: 0, height: 300)) == .bottomTrailing)
        #expect(corner(from: .bottomLeading, by: CGSize(width: 260, height: -300)) == .topTrailing)
    }

    /// In right to left, top trailing is the top left: a drag to the right goes to the leading corner.
    @Test
    func rightToLeftMirrorsTheCorners() {
        #expect(corner(from: .topTrailing, by: CGSize(width: 250, height: 0), isRightToLeft: true) == .topLeading)
        #expect(corner(from: .topLeading, by: CGSize(width: -250, height: 300), isRightToLeft: true) == .bottomTrailing)
    }

    private func corner(from start: Alignment, by translation: CGSize, isRightToLeft: Bool = false) -> Alignment {
        NativeCallCornerTile.nearestCorner(from: start, translation: translation, in: size, tileSize: tile, isRightToLeft: isRightToLeft)
    }
}
