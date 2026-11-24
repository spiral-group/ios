//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import XCTest

// AGENT-PLATFORM (Brief 0083 L1c): Spiral's stricter audit for the previews that
// conform to `SpiralGatedPreview`, listed in GeneratedSpiralGatedAccessibilityTests.swift.
// Upstream's audit leaves out `contrast` and `textClipped`; Spiral's has them, and
// runs once in light and once in dark, because each appearance has its own colours.

extension AccessibilityTests {
    /// One launch of the app that audits every state of a preview.
    struct Audit {
        /// `light` or `dark` (`ACCESSIBILITY_APPEARANCE`); `nil` keeps the simulator's, as upstream does.
        let appearance: String?
        let types: XCUIAccessibilityAuditType
        /// Spiral's audit holds its contrast issues back. A state that has any is audited for contrast again
        /// (`contrastRecheck`) once the app has left out what the gate exempts (`SpiralContrastExemptions`),
        /// and only that audit's issues count. On iOS 27 a contrast issue on SwiftUI text has no element,
        /// so the runner can't tell an exempt one from the others. The bars are measured by their pixels
        /// (`checkBarContrast`).
        var defersContrast = false
        var isContrastRecheck = false
        /// Where the navigation bars end, as the first audit read them: the recheck's, for contrast triage J.
        var headerBottom: CGFloat?
        /// The app's scroll views that can't scroll, on the screen: the recheck's, for contrast triage L.
        var fixedScrollViewFrames: [CGRect] = []

        var contrastRecheck: Audit {
            Audit(appearance: appearance, types: .contrast, isContrastRecheck: true)
        }

        func activityName(forPreviewNamed name: String) -> String {
            let details = [appearance, isContrastRecheck ? "contrast" : nil].compactMap(\.self)
            return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
        }
    }

    /// What a state's first audit leaves for its contrast recheck.
    struct AuditOutcome {
        /// Whether contrast issues were held back for `Audit.contrastRecheck`.
        var heldContrastBack = false
        /// The frames of everything in the bars (`checkBarContrast`), to compare with what the app hides.
        var barFrames = BarFrames()
    }

    /// Fixture states that must fail, so a gate that stopped failing shows. The first audit must fail on the
    /// pixels of a navigation bar and of a toolbar, and on a toolbar element it can't read; the contrast
    /// recheck on the content. Each is a strict `XCTExpectFailure`.
    static let statesExpectedToFail: Set = ["SpiralGatesFixture_Previews-Low contrast"]
    /// A known contrast failure: the audit issue's description and the element it must be on.
    struct KnownFailure {
        let description: String
        let elementType: XCUIElement.ElementType
        let elementLabel: String

        static let catalogueChip = KnownFailure(description: "Contrast failed", elementType: .staticText, elementLabel: "For the whole chat")
        static let createAgent = KnownFailure(description: "Contrast failed", elementType: .staticText, elementLabel: "Create an agent")

        static func emptyState(_ title: String) -> KnownFailure {
            KnownFailure(description: "Contrast failed", elementType: .staticText, elementLabel: title)
        }
        
        /// White on the start screen's light blue, kept by the operator (`knownFailures`, 2026-11-20).
        static func startScreenBlue(_ label: String, _ elementType: XCUIElement.ElementType = .staticText, nearlyPassed: Bool = false) -> KnownFailure {
            KnownFailure(description: nearlyPassed ? "Contrast nearly passed" : "Contrast failed", elementType: elementType, elementLabel: label)
        }
    }
    
    /// The start screen's slide, brand and frosted button on the blue, in every light state.
    private static func startScreenBlueFailures(frostedButton: String, invitation: [KnownFailure] = []) -> [ExpectedFailure] {
        ([KnownFailure.startScreenBlue("Spiral"),
          .startScreenBlue("Your conversations are yours"),
          .startScreenBlue("End-to-end encryption. No phone number, and your assistant only with your permission"),
          .startScreenBlue(frostedButton, .button)] + invitation).map { .knownContrast($0) }
    }

    /// Known failures that wait for a later fix, by state and appearance: the failures the state must have, in the audit
    /// that has them, under strict `XCTExpectFailure`s as for a state that must fail. Their matchers take only those
    /// failures, so any other issue still fails the test, and a fix shows.
    private static let knownFailures: [String: [ExpectedFailure]] = [
        // The Agents tab's badge in the audit's window only: that window draws it in the system red (#FF383C light,
        // #FF4245 dark), where its white count reads 3.57:1 and 3.43:1, and the bar reader measures it on its own (`checkTab`).
        // The app sets bgAccentRest on every layout (decision 306, 4.81:1) and the snapshots show it so; the audit's
        // window doesn't take the tab bar's appearance. Strict: once that window draws the app's badge, the state stops
        // failing and the test fails, so the entry is removed. DEBT: the audit's window draws the system badge.
        "ApprovalDetailScreen_Previews-In the Agents tab (light)": [.badgeContrast(in: "tab bar", label: "Agents")],
        // And in dark, Chats' and Feed's glyphs don't show: the audit's window and the dark snapshot draw them dark on the
        // dark glass, where the bar reader finds no icon over the title ("nothing to measure" for Chats' icon, one run of
        // rows for Feed). The glyphs are drawn ahead by ImageRenderer (decision 386), which seems to resolve Compound's
        // colours by the app's light traits rather than the window's dark, as the selected Agents glyph is light-mode blue
        // (#2A61CF) there too. Whether a phone in dark mode shows them right is step 8's check (DEBT). Strict.
        "ApprovalDetailScreen_Previews-In the Agents tab (dark)": [.badgeContrast(in: "tab bar", label: "Agents"),
                                                                   .unreadableBarElement(in: "tab bar", label: "Chats"),
                                                                   .unreadableBarElement(in: "tab bar", label: "Feed")],
        // Must-fail states for contrast triage K (`SpiralGatesPixelFixture`): small text at about 4:1 on the Mist, a square
        // button whose label is text at 4.05:1, and 17 pt text with «(» and «Ї» at 3.55:1. Apple's audit fails each, and the
        // runner's reading of their pixels must not rescue any (Opus review, 2026-11-14). Apple's audit calls each "Contrast
        // nearly passed" (3–4.5:1). Strict, each on its label.
        "SpiralGatesFixture_Previews-Pixels can't rescue (light)": SpiralGatesPixelFixtureFailures.all,
        "SpiralGatesFixture_Previews-Pixels can't rescue (dark)": SpiralGatesPixelFixtureFailures.all,
        // Misreads of Apple's audit on the catalogue that the element's own pixels can't overrule (contrast triage K), each
        // checked on the audit's screenshots in step 5 (2026-11-14, ledger § 3, iOS fix/1.0.2-contrast-feed-catalogue):
        // - a fact chip's text with its symbol: one element of two colours to the reader; the text is #1C1C1E on #C3E2FF
        //   glass (12.67:1) and white on #2B417E (9.72:1), the symbol 5.14:1 and 4.37:1 (a graphic, 3:1);
        // - «Create an agent», #2455B5 on #B5DCFF (4.82:1) and #6CB2FF on #283C73 (4.76:1): over 4.5:1 by less than the
        //   reader's margin of a tenth;
        // - an empty or error state's title, read with its symbol above it: the title is #1C1C1E or white on the Mist
        //   (11.5:1 and up), the symbol 8.96:1 and 6.26:1.
        // Strict, each on its label: when the audit reads one right or its layout changes, the state stops failing there and
        // the test fails, so the entry goes. DEBT: Apple's audit misreads text on the Mist and on glass over it.
        "InteractivePostCatalogPostScreen_Previews-Filled in with the agent (light)": [.knownContrast(.catalogueChip)],
        "InteractivePostCatalogPostScreen_Previews-Filled in, no agent (light)": [.knownContrast(.catalogueChip), .knownContrast(.createAgent)],
        "InteractivePostCatalogPostScreen_Previews-Filled in, no agent (dark)": [.knownContrast(.createAgent)],
        "InteractivePostCatalogPostScreen_Previews-Filled in, the agent setting up (light)": [.knownContrast(.catalogueChip)],
        "InteractivePostCatalogPostScreen_Previews-Filled in, the agents unread (light)": [.knownContrast(.catalogueChip)],
        "InteractivePostCatalogPostScreen_Previews-Send (dark)": [.knownContrast(.catalogueChip)],
        "InteractivePostCatalogPostScreen_Previews-Send to a long room name (dark)": [.knownContrast(.catalogueChip)],
        "InteractivePostCatalogPostScreen_Previews-Send, no agent (dark)": [.knownContrast(.catalogueChip)],
        "InteractivePostCatalogScreen_Previews-Failure (light)": [.knownContrast(.emptyState("Couldn't load the catalog"))],
        "InteractivePostCatalogScreen_Previews-Failure (dark)": [.knownContrast(.emptyState("Couldn't load the catalog"))],
        "InteractivePostCatalogScreen_Previews-Needs a newer app (light)": [.knownContrast(.emptyState("Update the app to open it"))],
        "InteractivePostCatalogScreen_Previews-Needs a newer app (dark)": [.knownContrast(.emptyState("Update the app to open it"))],
        "InteractivePostCatalogScreen_Previews-Search found nothing (light)": [.knownContrast(.emptyState("Nothing like that yet"))],
        "InteractivePostCatalogScreen_Previews-Search found nothing (dark)": [.knownContrast(.emptyState("Nothing like that yet"))],
        "InteractivePostCatalogScreen_Previews-Search found nothing, no agent (light)": [.knownContrast(.emptyState("Nothing like that yet"))],
        "InteractivePostCatalogScreen_Previews-Search found nothing, no agent (dark)": [.knownContrast(.emptyState("Nothing like that yet"))],
        // The bar reader can't read the agent's header: the title capsule is read whole with the agent's avatar inside
        // it, the Peek's purple gradient a varied backdrop to the title, and the Peek itself, white on that gradient, has
        // no one background (read by its extreme it is #FFFFFF on #8C75B4, 3.95:1, in light). The audit's screenshots
        // show the title and the Peek clear in both appearances. DEBT (end stage 2026-11-14): teach the reader a
        // capsule's avatar.
        // The start screen keeps the 1.0.2 App Store blue (#6C9BF4 → #2E62DE): the operator decided on 2026-11-20 to leave
        // it as it is («Лишай як є») after seeing the numbers. In light, the white slide text, the brand name, the frosted
        // button and the invitation's lines read 2.8–3.5:1 by the audit's pixels (the slide's top is the lightest); dark
        // passes, and Increase Contrast deepens the blue (its colour sets). Strict, each on its label: if the blue or the
        // layout changes, the state stops failing there and the test fails, so the entry goes.
        "AuthenticationStartScreen_Previews-Default (light)": startScreenBlueFailures(frostedButton: "Create account"),
        "AuthenticationStartScreen_Previews-Invited (light)": startScreenBlueFailures(frostedButton: "Sign in", invitation: [
            .startScreenBlue("Alice invited you to Spiral", nearlyPassed: true),
            .startScreenBlue("Create an account and Alice will know you're here")
        ]),
        "AuthenticationStartScreen_Previews-Invited by a campaign (light)": startScreenBlueFailures(frostedButton: "Sign in", invitation: [
            .startScreenBlue("You were invited to Spiral", nearlyPassed: true),
            .startScreenBlue("Create an account to join.")
        ]),
        "RoomScreen_Previews-Assistant DM (light)": [.unreadableBarElement(in: "navigation bar", label: "App Review · assistant"),
                                                     .unreadableBarElement(in: "navigation bar", label: "spiral.peek.fill")],
        "RoomScreen_Previews-Assistant DM (dark)": [.unreadableBarElement(in: "navigation bar", label: "App Review · assistant"),
                                                    .unreadableBarElement(in: "navigation bar", label: "spiral.peek.fill")],
        // 1.0.3 A2: the assistant's chat before consent has the same capsule header as its chat, so the same misread.
        "JoinRoomAssistantInviteView_Previews-Own assistant (light)": [.unreadableBarElement(in: "navigation bar", label: "Your assistant"),
                                                                       .unreadableBarElement(in: "navigation bar", label: "spiral.peek.fill")],
        "JoinRoomAssistantInviteView_Previews-Own assistant (dark)": [.unreadableBarElement(in: "navigation bar", label: "Your assistant"),
                                                                      .unreadableBarElement(in: "navigation bar", label: "spiral.peek.fill")]
    ]
    /// The must-fail states the current launch showed, and those whose contrast recheck hasn't run yet.
    private static var mustFailStatesShown = Set<String>()
    private static var rechecksOwed = Set<String>()
    /// The labels of the known contrast failures the current recheck has shown (`isKnownFailureElsewhere`).
    private static var knownLabelsSeen = Set<String>()

    static let upstreamAuditTypes: XCUIAccessibilityAuditType = [.dynamicType, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
    /// The two types upstream left out "for now".
    static let spiralAuditTypes: XCUIAccessibilityAuditType = [.contrast, .textClipped]

    static func audits(forPreviewNamed name: String) -> [Audit] {
        guard spiralGatedPreviews.contains(name) else {
            return [Audit(appearance: nil, types: upstreamAuditTypes)]
        }

        let types = upstreamAuditTypes.union(spiralAuditTypes)
        return [Audit(appearance: "light", types: types, defersContrast: true), Audit(appearance: "dark", types: types, defersContrast: true)]
    }

    /// A state that must fail proves the gate only while its preview is gated, so deleting the fixture fails here.
    /// A known failure's preview must be gated too, or its expectation would never run.
    func testStatesThatMustFailAreGated() {
        for state in Self.statesExpectedToFail.sorted() + Self.knownFailures.keys.sorted() {
            let preview = String(state.prefix { $0 != "-" })
            XCTAssert(Self.spiralGatedPreviews.contains(preview), "\(state) must fail, but \(preview) is no SpiralGatedPreview")
        }
    }

    /// Runs a state's audit, under strict expected failures when the state must fail (`statesExpectedToFail`,
    /// `knownFailures`). Only the failures that audit must have are expected; any other still fails the test.
    static func expectingFailure<Result>(ofStateNamed name: String, in audit: Audit, _ body: () -> Result) -> Result {
        let state = "\(name) (\(audit.appearance ?? "default"))"
        let failures: [ExpectedFailure]
        if let known = knownFailures[state] {
            // The known contrast failures of one state share one expectation per description: the audit's issues carry no
            // element to the expectation, so each label is checked in `isKnownFailureElsewhere` and after the audit.
            var descriptions = Set<String>()
            failures = known.filter { failure in
                guard failure.isInContrastRecheck == audit.isContrastRecheck else { return false }
                guard case .knownContrast(let knownFailure) = failure else { return true }
                return descriptions.insert(knownFailure.description).inserted
            }
        } else if statesExpectedToFail.contains(name) {
            failures = audit.isContrastRecheck
                ? [.contentContrast]
                : [.barContrast(in: "navigation bar"), .barContrast(in: "toolbar"), .unreadableBarElement(in: "toolbar")]
        } else {
            return body()
        }
        let result = expecting(failures[...], in: audit.activityName(forPreviewNamed: name), body)

        if audit.isContrastRecheck {
            rechecksOwed.remove(state)
            // Each known contrast failure must show on its own element, so a fix shows even while another stays.
            for knownFailure in knownContrastFailures(ofStateNamed: state) where !knownLabelsSeen.contains(knownFailure.elementLabel) {
                XCTFail("\(audit.activityName(forPreviewNamed: name)) must fail with \"\(knownFailure.description)\" on '\(knownFailure.elementLabel)', which it didn't")
            }
            knownLabelsSeen.removeAll()
        } else {
            mustFailStatesShown.insert(state)
            // A known failure of the first audit owes no recheck: its state may hold no contrast issue back.
            if knownFailures[state].map({ $0.contains(where: \.isInContrastRecheck) }) ?? true {
                rechecksOwed.insert(state)
            }
        }
        return result
    }

    /// Fails for what a launch owed its must-fail states: each must show, so that deleting one can't remove the
    /// self-test, and each must have had its contrast recheck. Called at the end of every launch, after a throw too.
    static func failForMustFailStatesNotChecked(inPreviewNamed name: String, appearance: String?) {
        let unshown = statesExpectedToFail.filter { $0.hasPrefix("\(name)-") && !mustFailStatesShown.contains("\($0) (\(appearance ?? "default"))") }
        for state in unshown.sorted() {
            XCTFail("\(state) (\(appearance ?? "default")) must fail, but the launch never showed it")
        }
        let unshownKnown = knownFailures.keys.filter { state in
            state.hasPrefix("\(name)-") && state.hasSuffix(" (\(appearance ?? "default"))") && !mustFailStatesShown.contains(state)
        }
        for state in unshownKnown.sorted() {
            XCTFail("\(state) must fail, but the launch never showed it")
        }
        for state in rechecksOwed.sorted() {
            XCTFail("\(state) must fail its contrast recheck, which never ran")
        }
        mustFailStatesShown.removeAll()
        rechecksOwed.removeAll()
    }

    /// Whether a contrast recheck's issue reads like the state's known failure but lies on another element. It fails
    /// the test with a message of its own, which the known failure's matcher doesn't take, and the audit's issue is
    /// left out, so the expectation can't absorb it.
    static func isKnownFailureElsewhere(_ issue: XCUIAccessibilityAuditIssue, previewNamed name: String, in audit: Audit) -> Bool {
        let known = knownContrastFailures(ofStateNamed: "\(name) (\(audit.appearance ?? "default"))").filter { $0.description == issue.compactDescription }
        guard audit.isContrastRecheck, !known.isEmpty else {
            return false
        }
        if let element = issue.element,
           let knownFailure = known.first(where: { $0.elementType == element.elementType && $0.elementLabel == element.label }) {
            knownLabelsSeen.insert(knownFailure.elementLabel)
            return false
        }

        let place = issue.element.map { "'\($0.label)'" } ?? "an element the audit didn't name"
        let labels = known.map { "'\($0.elementLabel)'" }.joined(separator: ", ")
        XCTFail("\(audit.activityName(forPreviewNamed: name)): \(issue.compactDescription) on \(place), not on the known failures' \(labels)")
        return true
    }

    private static func knownContrastFailures(ofStateNamed state: String) -> [KnownFailure] {
        (knownFailures[state] ?? []).compactMap { failure in
            if case .knownContrast(let knownFailure) = failure { knownFailure } else { nil }
        }
    }

    /// Fails for each element the app hid with the bars that no bar the runner measures holds: nothing would have
    /// checked its contrast, neither the recheck nor `checkBarContrast`.
    static func failForHiddenElementsOutsideBars(_ hiddenElements: [UITestsSignal.AccessibilityAudit.HiddenElement], barFrames: [CGRect], stateNamed name: String) {
        for element in hiddenElements where !barFrames.contains(where: { $0.matches(element.frame) }) {
            XCTFail("\(name): the app hid '\(element.label)' at \(element.frame) from the contrast recheck, but no navigation bar, toolbar or tab bar holds it")
        }
    }

    /// A held contrast issue, for an opt-in's review to see that each is a bar's (cause A) or an inactive control's (B).
    static func reportHeldContrastIssue(_ issue: XCUIAccessibilityAuditIssue, previewNamed name: String) {
        // swiftlint:disable:next print_deprecation
        print("🔍 A11Y HELD [\(name)] desc=\(issue.compactDescription) detail=\(issue.detailedDescription) element=\(issue.element?.debugDescription ?? "nil")")
    }

    /// Whether Spiral's audit leaves a contrast issue out (Brief 0083): a colour emoji's own colours (contrast triage H),
    /// text its list has scrolled out of sight (I), its header cuts (J) or its list's bottom edge cuts (L), or an
    /// inactive control (B), each printed as an `A11Y EXEMPT` line for a review to check. It needs the issue's element: on iOS 27 only the recheck's
    /// contrast issues carry one, so the first audit holds these too and the recheck names them.
    static func isExemptContrastIssue(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication, previewNamed name: String,
                                      headerBottom: CGFloat? = nil, fixedScrollViewFrames: [CGRect] = [],
                                      readsOwnPixels: Bool = false) -> Bool {
        guard issue.auditType == .contrast, let element = issue.element else { return false }

        let cause: String
        if isEmojiOnlyText(element) {
            cause = "H (emoji)"
        } else if isScrolledOutOfSight(element, in: app) {
            cause = "I (scrolled out of sight)"
        } else if let headerBottom, isCutByHeader(element, headerBottom: headerBottom, previewNamed: name, in: app) {
            cause = "J (cut by the header)"
        } else if let shown = shownAboveListBottom(element, fixedScrollViewFrames: fixedScrollViewFrames, in: app) {
            cause = String(format: "L (cut by its list's bottom edge, %.0f%% of it shows)", shown * 100)
        } else if element.elementType == .button, !element.isEnabled {
            // WCAG 1.4.3 exempts an inactive control. The app covers the ones it finds for the recheck
            // (`SpiralContrastExemptions`), and this is the same rule for one it can't cover: the runner reads the
            // control's disabled state from the element the audit names, so only a disabled button is left out, and
            // its label and frame are printed. Seen on ApprovalDetailScreen's decision bar while it loads: its
            // placeholder buttons reach the audit though they and the preloader are hidden from accessibility.
            cause = "B (an inactive control)"
        } else if readsOwnPixels, let reading = ownPixelsPass(element, previewNamed: name) {
            cause = "K (its own pixels pass: \(reading))"
        } else {
            return false
        }
        // swiftlint:disable:next print_deprecation
        print("🔍 A11Y EXEMPT [\(name)] cause=\(cause) desc=\(issue.compactDescription) element=\(element.debugDescription)")
        return true
    }

    /// Contrast triage K: the recheck's issue on an element whose own pixels, on the screen the audit measured, read above
    /// the ratio WCAG asks of it by a tenth more, the width of one band of the reader's shades (`BarReading`). Apple's audit
    /// fails text on the Mist and on glass over it that measures 5.7–12.7:1, and a monogram through its button's 44 pt
    /// frame (step 5, 2026-11-14). The element is read as the bars are: text needs 4.5:1, or 3:1 when its ink is 18 pt
    /// tall; a monogram is read on its own disc. A reading that can't tell the element's text from what is around it (a
    /// second colour, a varied backdrop) leaves the issue standing. Each reading is printed, issue or not.
    private static func ownPixelsPass(_ element: XCUIElement, previewNamed name: String) -> String? {
        let reading = ownPixelsReading(of: element, stateNamed: name)
        // swiftlint:disable:next print_deprecation
        print("🔍 A11Y PIXELS [\(name)] \(reading.passes ? "passes" : "stands"): \(reading.description)")
        return reading.passes ? reading.description : nil
    }

    /// A text element that holds only emoji (contrast triage H). The audit takes a colour emoji's own colours for the
    /// text colour: beside a count, a reaction pill's emoji is a text element of its own, and 🤯, 🎉 or 😅 fail on the
    /// pill's grey whatever colour is set. There is no text colour to set, and the count and text keys beside it
    /// stay audited.
    private static func isEmojiOnlyText(_ element: XCUIElement) -> Bool {
        element.elementType == .staticText && isEmojiOnly(element.label)
    }

    private static func isEmojiOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { character in
            let scalars = character.unicodeScalars
            // A pictograph, or a sequence that starts with one: ❤️, #️⃣, 🤷‍♂️. A lone digit or "#" is text.
            return scalars.contains { $0.properties.isEmojiPresentation } || (scalars.count > 1 && scalars.first?.properties.isEmoji == true)
        }
    }

    /// Text that its own list has scrolled wholly out of sight (contrast triage I). The top cell of a timeline keeps
    /// its sender's avatar and name in the hierarchy at the frame they would have, above the list, and the audit
    /// measures the navigation bar there. Only a descendant of the list counts: the bar's own items lie outside the
    /// list too, and they stay audited. Text the list's edge cuts through is partly on screen, and stays audited.
    private static func isScrolledOutOfSight(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        // The app's whole tree: a list's own snapshot leaves out the children outside its bounds.
        guard let root = try? app.snapshot() else { return false }
        return root.holdsOutOfSight(element.elementType, label: element.label, frame: element.frame, insideListFrame: nil)
    }

    /// How far below the navigation bar the system's scroll edge effect still fades what scrolls under it, for the
    /// timelines only (`timelinePreviews`): their top row's sender name sits 12 pt under the bar.
    private static let headerEdgeDepth: CGFloat = 20
    /// The previews that sit scrolled to the newest message, so their top row is always cut by the header.
    private static let timelinePreviews = ["RoomScreen_Previews-", "RoomScreenTimeline_Previews-", "SpiralConversation_Previews-",
                                           "InteractivePostTimeline_Previews-"]

    /// A small element of a list that the header cuts (contrast triage J): the top row of a timeline, scrolled under
    /// the bar where the preview sits at the newest message. The audit measures it against the bar's glass and the
    /// scroll edge effect's fade, which make text there unreadable on purpose; it scrolls into clear view. All of:
    /// - it is a descendant of a list, and another element of that list starts above the bar's bottom: content really
    ///   runs under the bar, which a list at rest at its top doesn't;
    /// - it starts above the bar's bottom, or, in a timeline preview, within `headerEdgeDepth` of it;
    /// - it ends within twice that depth of the bar's bottom: a row's name, time or avatar, never a paragraph that
    ///   merely starts there.
    /// The bar's own items are measured by `checkBarContrast`, and everything else stays audited.
    private static func isCutByHeader(_ element: XCUIElement, headerBottom: CGFloat, previewNamed name: String, in app: XCUIApplication) -> Bool {
        let frame = element.frame
        let isTimeline = timelinePreviews.contains { name.hasPrefix($0) }
        guard frame.minY < headerBottom + (isTimeline ? headerEdgeDepth : 0),
              frame.maxY <= headerBottom + 2 * headerEdgeDepth,
              let root = try? app.snapshot(),
              let list = root.list(holding: element.elementType, label: element.label, frame: frame, nearestList: nil) else {
            return false
        }
        return list.hasDescendant { !$0.frame.isClose(to: frame) && !$0.frame.isEmpty && $0.frame.minY < headerBottom }
    }
    
    /// Text that its own list's bottom edge cuts through its glyphs (contrast triage L): a row the list has half scrolled
    /// into view, such as a cold outreach's "Expires" just above ApprovalDetailScreen's decision bar (1.0.3 carry-over).
    /// The audit measures only the visible strip of the letters and calls it faint (1.23:1), though the text colour
    /// passes; the row scrolls into clear view. All of:
    /// - it is static text, never a button, an image or an avatar;
    /// - its nearest scroll container is a list (a table or a collection view: SwiftUI's `List` and `Form`), not a
    ///   plain scroll view, which may draw what crosses its edge whole (`scrollClipDisabled`);
    /// - that list can scroll (the app reports the ones that can't, such as a list under `scrollDisabled`);
    /// - the list's bottom edge runs through it, and less than half of its height shows above the edge: the audit read
    ///   too little of it to judge, while text that mostly shows stays audited;
    /// - it is no taller than `cutRowMaxHeight`: a row's title or value, never a paragraph whose top lines show whole.
    /// Text wholly inside the list stays audited, and wholly outside it is triage I.
    /// - Returns: The share of the element's height that shows, or `nil` when it isn't such a row.
    private static func shownAboveListBottom(_ element: XCUIElement, fixedScrollViewFrames: [CGRect], in app: XCUIApplication) -> CGFloat? {
        let frame = element.frame
        guard element.elementType == .staticText,
              frame.height <= cutRowMaxHeight,
              let root = try? app.snapshot(),
              let list = root.list(holding: element.elementType, label: element.label, frame: frame, nearestList: nil),
              [.table, .collectionView].contains(list.elementType) else {
            return nil
        }
        let bottom = list.frame.maxY
        let shown = bottom - frame.minY
        guard shown > 0, shown < frame.height / 2 else { return nil }
        // A list that can't scroll: the app's frame for it ends where the list does and holds the element's top.
        let isFixed = fixedScrollViewFrames.contains { abs($0.maxY - bottom) < 2 && $0.minY <= frame.minY && $0.minX <= frame.midX && $0.maxX >= frame.midX }
        return isFixed ? nil : shown / frame.height
    }

    /// The tallest element triage L takes for a cut row's text: two lines of body text at the default size.
    private static let cutRowMaxHeight: CGFloat = 48

    /// Upstream ignores every issue without an element as a false positive. A contrast or clipping
    /// issue on SwiftUI text often has none (its detail names a `SwiftUI.AccessibilityNode`), and
    /// ignoring it would let the gate pass on a real failure, so those count and are printed here.
    static func reportsIssueWithoutElement(_ issue: XCUIAccessibilityAuditIssue, previewNamed name: String) -> Bool {
        guard spiralAuditTypes.contains(issue.auditType) else { return false }

        // swiftlint:disable:next print_deprecation
        print("🔍 A11Y ISSUE [\(name)] type=\(issue.auditType) desc=\(issue.compactDescription) detail=\(issue.detailedDescription) element=nil")
        return true
    }

    /// Runs `body` under one strict expected failure for each of `failures`: each must happen.
    private static func expecting<Result>(_ failures: ArraySlice<ExpectedFailure>, in activity: String, _ body: () -> Result) -> Result {
        guard let failure = failures.first else { return body() }

        let options = XCTExpectedFailure.Options()
        options.isStrict = true
        options.issueMatcher = { failure.matches($0) }
        return XCTExpectFailure("\(activity): \(failure.reason)", options: options) {
            expecting(failures.dropFirst(), in: activity, body)
        }
    }
}

/// A failure that a must-fail state's audit, or a known failure's, must have.
private enum ExpectedFailure {
    /// `checkBarContrast` measured text under its ratio in this kind of bar.
    case barContrast(in: String)
    /// `checkBarContrast` couldn't tell an element's text from what surrounds it in this kind of bar; with a
    /// label, only that element's reading.
    case unreadableBarElement(in: String, label: String? = nil)
    /// `checkBarContrast` measured the count of a tab's badge under its ratio, on the tab of this label.
    case badgeContrast(in: String, label: String)
    /// The contrast recheck failed the content.
    case contentContrast
    /// The contrast recheck failed the content with exactly this description: a known failure (`knownFailures`). The
    /// issue is on its element: `isKnownFailureElsewhere` fails the same description anywhere else first.
    case knownContrast(AccessibilityTests.KnownFailure)

    /// Whether the contrast recheck has this failure; the first audit has `checkBarContrast`'s.
    var isInContrastRecheck: Bool {
        switch self {
        case .barContrast, .unreadableBarElement, .badgeContrast: false
        case .contentContrast, .knownContrast: true
        }
    }

    var reason: String {
        switch self {
        case .barContrast(let bar): "a label on blue in its \(bar) must fail the bars' pixels"
        case .unreadableBarElement(let bar, nil): "a text in two colours in its \(bar) must fail as unreadable"
        case .unreadableBarElement(let bar, let label?): "its \(bar)'s '\(label)' reads as unreadable, a known false failure"
        case .badgeContrast(let bar, let label): "its \(bar)'s badge on '\(label)' is the audit window's system red, a known failure of that window"
        case .contentContrast: "its faint text must fail the contrast recheck"
        case .knownContrast(let known): "a known failure until its fix lands (DEBT): it must fail with \"\(known.description)\" on '\(known.elementLabel)'"
        }
    }

    /// XCTFail's issues read "failed - <message>"; the audit's read "Contrast failed".
    func matches(_ issue: XCTIssue) -> Bool {
        switch self {
        case .barContrast(let bar): issue.compactDescription.contains("\(AccessibilityTests.barContrastFailure) \(bar):")
        case .unreadableBarElement(let bar, let label):
            issue.compactDescription.contains("\(AccessibilityTests.barReadingFailure) \(bar):")
                && label.map { issue.compactDescription.contains("'\($0)' at") } ?? true
        case .badgeContrast(let bar, let label):
            issue.compactDescription.contains("\(AccessibilityTests.barContrastFailure) \(bar):")
                && issue.compactDescription.contains("the badge of '\(label)' at")
        case .contentContrast: issue.compactDescription.hasPrefix("Contrast")
        case .knownContrast(let known): issue.compactDescription == known.description
        }
    }
}

private extension CGRect {
    /// The same frame, give or take a point: the app and the runner each read it from accessibility.
    func matches(_ other: CGRect) -> Bool {
        abs(minX - other.minX) <= 1 && abs(minY - other.minY) <= 1 && abs(width - other.width) <= 1 && abs(height - other.height) <= 1
    }
}

private extension XCUIElementSnapshot {
    /// The nearest list above the element in the tree, nil when it isn't in one.
    func list(holding elementType: XCUIElement.ElementType, label: String, frame: CGRect, nearestList: XCUIElementSnapshot?) -> XCUIElementSnapshot? {
        let nearestList = [.table, .collectionView, .scrollView].contains(self.elementType) ? self : nearestList
        for child in children {
            if child.elementType == elementType, child.label == label, child.frame.isClose(to: frame) {
                return nearestList
            }
            if let list = child.list(holding: elementType, label: label, frame: frame, nearestList: nearestList) {
                return list
            }
        }
        return nil
    }

    /// Whether any element below this one passes `test`.
    func hasDescendant(_ test: (XCUIElementSnapshot) -> Bool) -> Bool {
        children.contains { test($0) || $0.hasDescendant(test) }
    }

    /// Whether the tree holds the element below a list (the nearest one) whose frame it lies wholly outside.
    func holdsOutOfSight(_ elementType: XCUIElement.ElementType, label: String, frame: CGRect, insideListFrame listFrame: CGRect?) -> Bool {
        let listTypes: [XCUIElement.ElementType] = [.table, .collectionView, .scrollView]
        let listFrame = listTypes.contains(self.elementType) ? self.frame : listFrame
        return children.contains { child in
            if child.elementType == elementType, child.label == label, child.frame.isClose(to: frame) {
                return listFrame.map { !$0.intersects(frame) } ?? false
            }
            return child.holdsOutOfSight(elementType, label: label, frame: frame, insideListFrame: listFrame)
        }
    }
}

private extension CGRect {
    func isClose(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 1 && abs(minY - other.minY) < 1 && abs(width - other.width) < 1 && abs(height - other.height) < 1
    }
}

/// The failures `SpiralGatesPixelFixture` must keep, in both appearances.
private enum SpiralGatesPixelFixtureFailures {
    static let all: [ExpectedFailure] = [
        .knownContrast(.init(description: "Contrast nearly passed", elementType: .staticText, elementLabel: "Small text on the Mist")),
        .knownContrast(.init(description: "Contrast nearly passed", elementType: .button, elementLabel: "OK")),
        .knownContrast(.init(description: "Contrast nearly passed", elementType: .staticText, elementLabel: "Seventeen (Ї) points"))
    ]
}
