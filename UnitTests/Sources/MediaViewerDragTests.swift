//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import CoreGraphics
@testable import Spiral
import Testing

struct MediaViewerDragTests {
    private let height: CGFloat = 800

    @Test
    func aShortSlowDragSpringsBack() {
        let drag = MediaViewerDrag(translation: CGPoint(x: 0, y: 60), height: height)
        #expect(!drag.closes(velocity: 200))
    }

    @Test
    func aLongDragCloses() {
        let drag = MediaViewerDrag(translation: CGPoint(x: 0, y: 140), height: height)
        #expect(drag.closes(velocity: 0))
    }

    @Test
    func aFlickDownClosesHoweverShort() {
        let drag = MediaViewerDrag(translation: CGPoint(x: 0, y: 30), height: height)
        #expect(drag.closes(velocity: 1200))
        // A flick that ended above where it started doesn't.
        #expect(!MediaViewerDrag(translation: CGPoint(x: 0, y: -10), height: height).closes(velocity: 1200))
    }

    @Test
    func thePageFollowsTheFingerAndShrinks() {
        let halfway = MediaViewerDrag(translation: CGPoint(x: 10, y: 200), height: height)
        #expect(halfway.progress == 0.5)
        #expect(halfway.pageTransform.tx == 10)
        #expect(halfway.pageTransform.ty == 200)
        #expect(abs(halfway.pageTransform.a - 0.925) < 0.0001)

        // Past half the screen it stays at its smallest; dragged up it doesn't move up or grow.
        #expect(MediaViewerDrag(translation: CGPoint(x: 0, y: 700), height: height).progress == 1)
        let up = MediaViewerDrag(translation: CGPoint(x: 0, y: -50), height: height)
        #expect(up.progress == 0)
        #expect(up.pageTransform.ty == 0)
        #expect(up.pageTransform.a == 1)
    }
}
