//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A tap on a card's text opens the post and
// a tap on its link opens the link. The card's text used to be the chat's
// selectable `UITextView`, whose recognisers took the tap: nothing opened.
//

import XCTest

@MainActor
class FeedPostCardTests: XCTestCase {
    func testATapOnTheTextOpensThePostAndATapOnTheLinkOpensTheLink() {
        let app = Application.launch(.feedPostCard)

        let card = app.descendants(matching: .any)[A11yIdentifiers.feedScreen.postCard]
        XCTAssertTrue(card.waitForExistence(timeout: 10.0))
        let text = card.descendants(matching: .any)[A11yIdentifiers.feedScreen.postText]
        XCTAssertTrue(text.waitForExistence(timeout: 5.0), "the card's text is not in the tree")
        let actions = app.staticTexts["feed_card_harness-actions"]

        // The text's last lines are plain words: the link is on the first.
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        XCTAssertTrue(waitForLabel(of: actions, "openPost"), "a tap on the text did '\(actions.label)', not openPost alone")

        // The link is the text's first line, from its leading edge.
        text.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 10)).tap()
        // Only the link: a second openPost would push the post over the browser.
        XCTAssertTrue(waitForLabel(of: actions, "openPost, link https://example.org/garden"),
                      "after a tap on the link the card did '\(actions.label)', not the link alone")
    }

    private func waitForLabel(of element: XCUIElement, _ label: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5.0) == .completed
    }
}
