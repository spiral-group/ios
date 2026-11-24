//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 146): the flows several scenarios share — signing
// in on the dev MAS, the onboarding prompts, signing out, the seed-phrase
// registration on identity-login. The web pages run in SafariViewService,
// the sheet that asks to sign in in SpringBoard.
//
// Secrets: a password goes from its 0600 file to the field through the
// pasteboard, and the phrase words are read from the page and tapped by
// point, so neither appears in a query, an activity title or a log.
//

import UIKit
import XCTest

extension DevE2ETestCase {
    var homeAvatar: XCUIElement {
        element(A11yIdentifiers.homeScreen.userAvatar)
    }

    var startSignIn: XCUIElement {
        element(A11yIdentifiers.authenticationStartScreen.signIn)
    }

    /// The screens that can stand between a sign-in and the Chats list.
    var onboardingPrompts: [XCUIElement] {
        [element(A11yIdentifiers.identityConfirmationScreen.skip),
         element(A11yIdentifiers.notificationPermissionsScreen.notNow),
         element(A11yIdentifiers.aiConsentPromptScreen.allow)]
    }
    
    // MARK: - Accounts

    /// Launches the app and leaves `person` signed in on the Chats list,
    /// signing out whoever else is and walking the onboarding prompts.
    func ensureSignedIn(_ person: DevE2EFixture.Person, allowAI: Bool = true) async throws {
        if try await launchToKnownState(allowAI: allowAI) {
            if try currentAccount() == person.mxid { return }
            try signOut()
        }
        try await signInWithPassword(person)
        try completeOnboarding(allowAI: allowAI)
    }
    
    /// Launches the app and leaves it on the start screen.
    func ensureSignedOut() async throws {
        if try await launchToKnownState(allowAI: true) {
            try signOut()
        }
    }
    
    /// Launches the app; true when someone is signed in (and past the
    /// prompts a launch can show: the identity check, notifications, AI).
    func launchToKnownState(allowAI: Bool) async throws -> Bool {
        try await launchApp()
        guard let state = firstAppearing([startSignIn, homeAvatar] + onboardingPrompts, timeout: 60) else {
            throw DevE2EError.flow("the app showed neither the Chats list nor the start screen")
        }
        if state == 0 { return false }
        try completeOnboarding(allowAI: allowAI)
        return true
    }
    
    /// The MXID Settings shows; Settings is closed again.
    func currentAccount() throws -> String {
        try openSettings()
        let mxid = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '@' AND label ENDSWITH ':localhost'")).firstMatch
        try require(mxid, "the account's MXID in Settings")
        let value = mxid.label
        try closeSettings()
        return value
    }

    func openSettings() throws {
        try require(homeAvatar, timeout: 30, "the Chats list")
        homeAvatar.tap()
        try require(element(A11yIdentifiers.settingsScreen.account), "Settings")
    }

    /// Settings is a tab: leaving it is going back to Chats.
    func closeSettings() throws {
        try tap(element(A11yIdentifiers.homeTabs.chats), "the Chats tab")
        try require(element(A11yIdentifiers.homeScreen.startChat), "the Chats list")
    }

    func signOut() throws {
        try openSettings()
        let logout = element(A11yIdentifiers.settingsScreen.logout)
        for _ in 0..<4 where !logout.isHittable {
            app.swipeUp()
        }
        try tap(logout, "Settings › Sign out")
        let confirmations = [startSignIn,
                             app.alerts.buttons[A11yIdentifiers.alertInfo.primaryButton].firstMatch,
                             app.buttons.matching(NSPredicate(format: "label == 'Sign out'")).firstMatch]
        let end = Date().addingTimeInterval(60)
        while Date() < end {
            switch firstAppearing(confirmations, timeout: 5) {
            case 0: return
            case 1: confirmations[1].tap()
            case 2: if confirmations[2].isHittable { confirmations[2].tap() }
            default: break
            }
            settle(1)
        }
        throw DevE2EError.flow("signing out did not reach the start screen")
    }

    // MARK: - Sign in (dev MAS, password)

    func signInWithPassword(_ person: DevE2EFixture.Person) async throws {
        guard let passwordFile = person.passwordFile else { throw DevE2EError.flow("\(person.mxid) has no password file") }
        try tap(startSignIn, timeout: 30, "Sign in")
        try confirmWebAuthenticationSheet()

        let username = webView.textFields.matching(NSPredicate(format: "label CONTAINS[c] 'Username'")).firstMatch
        try passRememberedMASSession(until: username)
        try require(username, timeout: 30, "the MAS sign-in page")
        username.tap()
        settle(1)
        dismissKeyboardTip()
        username.typeText(person.localpart)

        let password = webView.secureTextFields.firstMatch
        try require(password, "the MAS password field")
        try await pasteSecret(fromFile: passwordFile, into: password)
        try tap(webView.buttons["Continue"].firstMatch, "MAS › Continue")
        try finishWebSignIn()
    }

    /// MAS remembers the last web session: a signed-in one offers «Sign out» /
    /// «Use another account», a deleted one «Account deleted» with «Sign in».
    func passRememberedMASSession(until page: XCUIElement) throws {
        let leave = webView.buttons.matching(NSPredicate(format: "label == 'Sign out' OR label == 'Use another account' OR label == 'Sign in'")).firstMatch
        for _ in 0..<3 {
            guard firstAppearing([page, leave], timeout: 30) == 1 else { return }
            leave.tap()
            settle(1)
        }
    }
    
    /// «"Spiral" Wants to Use "localhost" to Sign In» → Continue.
    func confirmWebAuthenticationSheet() throws {
        try tap(springboard.buttons["Continue"].firstMatch, timeout: 30, "the system sign-in sheet")
        try require(webView, timeout: 20, "the sign-in web sheet")
    }

    /// Save Password → Not Now; «Continue to Spiral?» → Continue; until the
    /// web sheet is gone.
    func finishWebSignIn() throws {
        let end = Date().addingTimeInterval(120)
        while Date() < end {
            for notNow in [app.buttons["Not Now"], springboard.buttons["Not Now"], webView.buttons["Not Now"]] where notNow.exists && notNow.isHittable {
                settle(1) // the sheet animates up; a tap while it moves misses
                // It may have gone meanwhile: a tap on a gone element fails the test.
                if notNow.exists, notNow.isHittable { notNow.tap() }
            }
            if webView.state != .runningForeground || !webView.webViews.firstMatch.exists {
                if app.wait(for: .runningForeground, timeout: 5) { return }
            }
            let consent = webView.buttons["Continue"].firstMatch
            if consent.exists, consent.isHittable {
                consent.tap()
            }
            settle(1)
        }
        throw DevE2EError.flow("the web sign-in did not hand back to the app")
    }

    /// Notifications → Not now, AI consent → Allow (or Not now), in either
    /// order; done when the Chats list shows with neither prompt on it.
    func completeOnboarding(allowAI: Bool) throws {
        let prompts = [element(A11yIdentifiers.identityConfirmationScreen.skip),
                       element(A11yIdentifiers.notificationPermissionsScreen.notNow),
                       element(allowAI ? A11yIdentifiers.aiConsentPromptScreen.allow : A11yIdentifiers.aiConsentPromptScreen.notNow)]
        let end = Date().addingTimeInterval(120)
        var quietSince: Date?
        while Date() < end {
            if let prompt = prompts.first(where: canTap) {
                prompt.tap()
                quietSince = nil
            } else if canTap(homeAvatar) {
                // Consent is fetched asynchronously: give it a moment to show.
                if let quietSince, Date().timeIntervalSince(quietSince) > 5 { return }
                quietSince = quietSince ?? Date()
            } else {
                quietSince = nil
            }
            settle(0.5)
        }
        throw DevE2EError.flow("the onboarding prompts did not end on the Chats list")
    }
    
    // MARK: - Secrets

    /// Puts the file's content into a field without typing it: the
    /// pasteboard, the field's Paste, the pasteboard emptied again.
    func pasteSecret(fromFile path: String, into field: XCUIElement) async throws {
        let secret = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw DevE2EError.flow("the secret file is empty") }
        // The keyboard's bar covers the next field: put the keyboard away first.
        dismissWebKeyboard()
        field.tap()
        settle(2)
        // Password AutoFill may ask for Face ID first; there is nothing saved to fill.
        if springboard.staticTexts["Face ID"].exists || webView.staticTexts["Face ID"].exists {
            try await helper.sim("faceid-nomatch")
            settle(2)
        }
        UIPasteboard.general.string = secret
        defer { UIPasteboard.general.items = [] }
        let pasteItems = [webView.menuItems["Paste"].firstMatch, webView.buttons["Paste"].firstMatch,
                          app.menuItems["Paste"].firstMatch, springboard.menuItems["Paste"].firstMatch]
        field.tap()
        if firstAppearing(pasteItems, timeout: 2) == nil {
            field.press(forDuration: 1.2)
        }
        guard let index = firstAppearing(pasteItems, timeout: 5) else {
            attachHierarchy("no Paste offered")
            throw DevE2EError.flow("the field offered no Paste")
        }
        pasteItems[index].tap()
        settle(1)
        guard (field.value as? String)?.count == secret.count else {
            throw DevE2EError.flow("the pasted secret did not land whole")
        }
    }
    
    /// The web sheet's and SpringBoard's element trees, for a step that
    /// could not find its control. Called before any secret is in a field.
    func attachHierarchy(_ name: String) {
        for (label, root) in [("web sheet", webView), ("springboard", springboard)] {
            let attachment = XCTAttachment(string: root.debugDescription)
            attachment.name = "\(name): \(label)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
    
    // MARK: - Registration (identity-login, seed phrase)

    /// From the start screen, the invitation `spiral://join/<inviteCode>`:
    /// Create account → the dev MAS → identity-login, the Terms ticked, the
    /// phrase read off the page and confirmed. With `checkTermsRefusal` it
    /// first submits without the tick and requires the page to refuse. With
    /// `inviter` the banner must name them before Create account.
    func registerWithSeedPhrase(_ person: DevE2EFixture.Person, inviteCode: String, inviter: String? = nil,
                                checkTermsRefusal: Bool) async throws {
        try await openLink("spiral://join/\(inviteCode)")
        let banner = element(A11yIdentifiers.authenticationStartScreen.invitedBanner)
        try require(banner, timeout: 30, "the invitation banner")
        if let inviter {
            // The banner says «You were invited» at once and the name once the link is resolved.
            let named = waitUntil(30) { banner.label.contains(inviter) }
            guard named else { throw DevE2EError.flow("the banner does not name \(inviter): '\(banner.label)'") }
        }
        try tap(element(A11yIdentifiers.authenticationStartScreen.createAccount), "Create account")
        try confirmWebAuthenticationSheet()

        let seedPhrase = webControl(NSPredicate(format: "label CONTAINS[c] 'Seed Phrase'"))
        try passRememberedMASSession(until: seedPhrase)
        try tap(seedPhrase, timeout: 30, "MAS › Continue with Seed Phrase")
        try tap(webControl(NSPredicate(format: "label == 'Create account'")), timeout: 30, "identity-login › the Create account tab")

        let username = webView.textFields["Username"].firstMatch
        try require(username, "identity-login › Username")
        username.tap()
        settle(1)
        dismissKeyboardTip()
        username.typeText(person.localpart)
        dismissWebKeyboard() // the keyboard's bar covers the next field
        let displayName = webView.textFields["Display name"].firstMatch
        displayName.tap()
        settle(1)
        displayName.typeText(person.displayName) // Cyrillic on purpose: typeText, not HID
        dismissWebKeyboard()

        let continueButton = webView.buttons.matching(NSPredicate(format: "label == 'Continue'")).firstMatch
        if checkTermsRefusal {
            try tap(continueButton, "identity-login › Continue without the Terms")
            let refusal = webView.staticTexts["Confirm you are 16 or older and accept the Terms of Use and the Privacy Policy to continue."].firstMatch
            guard refusal.waitForExistence(timeout: 10) else {
                throw DevE2EError.flow("identity-login went on without the Terms ticked")
            }
            guard !webView.buttons["Show"].exists else {
                throw DevE2EError.flow("the phrase step opened without the Terms ticked")
            }
        }
        try tickTerms()
        try tap(continueButton, "identity-login › Continue")

        try tap(webView.buttons["Show"].firstMatch, timeout: 30, "identity-login › Show the phrase")
        settle(1)
        _ = try readPhraseWords()
        // No word quiz since 2026-11-19: Show unlocked the tick, the tick
        // unlocks «Create account and sign in».
        let saved = webView.switches.matching(NSPredicate(format: "label BEGINSWITH 'I have saved the phrase'")).firstMatch
        try require(saved, "identity-login › I have saved the phrase")
        try revealInWeb(saved, "identity-login › I have saved the phrase")
        tapFrame(saved)
        settle(0.5)
        let create = webView.buttons["Create account and sign in"].firstMatch
        try require(create, "identity-login › Create account and sign in")
        try revealInWeb(create, "identity-login › Create account and sign in")
        guard create.isEnabled else { throw DevE2EError.flow("Create account stays off: the phrase was not acknowledged") }
        create.tap()
        try tap(webView.buttons["Skip"].firstMatch, timeout: 60, "identity-login › skip the passkey")
        try finishWebSignIn()
    }

    /// A button, link or tab on a web page: WebKit exposes `<a>` and
    /// `role=tab` as their own types.
    func webControl(_ predicate: NSPredicate) -> XCUIElement {
        let types = [XCUIElement.ElementType.button, .link, .tab].map(\.rawValue)
        let typed = NSPredicate(format: "elementType IN %@", types)
        return webView.descendants(matching: .any).matching(NSCompoundPredicate(andPredicateWithSubpredicates: [typed, predicate])).firstMatch
    }
    
    /// After a simulator reset (`spiral-dev-sim.sh reset`) the keyboard's
    /// first appearance covers its lower half with the slide-to-type tip
    /// («Speed up your typing…», Continue). Taps meant for the next field land
    /// on it, and its Continue is a second "Continue" on the web sheet: S02
    /// failed with "the field offered no Paste" that way (2026-10-14).
    func dismissKeyboardTip() {
        for root in [webView, app].compactMap(\.self) {
            let tip = root.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Speed up your typing'")).firstMatch
            guard tip.exists else { continue }
            let below = tip.frame.maxY
            let close = root.buttons.matching(NSPredicate(format: "label == 'Continue'")).allElementsBoundByIndex
                .first { $0.frame.minY > below && $0.isHittable }
            close?.tap()
            settle(1)
        }
    }
    
    func dismissWebKeyboard() {
        dismissKeyboardTip()
        for done in [webView.buttons["Done"].firstMatch, app.buttons["Done"].firstMatch, webView.toolbars.buttons.element(boundBy: 0)] where done.exists && done.isHittable {
            done.tap()
            break
        }
        settle(0.5)
    }

    private func tickTerms() throws {
        // The checkbox's text holds the Terms and Privacy links, and since
        // decision 205's «16 or older» it runs to two lines. WebKit may expose
        // the box, or only the text, with the whole row's frame: a tap on its
        // centre lands on a link and the sheet leaves the form. So tap the
        // row's left edge, where the box is.
        let predicate = NSPredicate(format: "label BEGINSWITH 'I am 16 or older and I agree to the'")
        let candidates = [webView.switches, webView.checkBoxes, webView.staticTexts].map { $0.matching(predicate).firstMatch }
        guard let row = firstAppearing(candidates, timeout: 20).map({ candidates[$0] }) else {
            throw DevE2EError.flow("identity-login › the Terms checkbox did not appear within 20 s")
        }
        // A coordinate tap skips XCUITest's own scrolling: bring the row into reach first.
        try revealInWeb(row, "identity-login › the Terms checkbox")
        let frame = row.frame
        let origin = webView.coordinate(withNormalizedOffset: .zero)
        // A box exposed on its own (a switch or checkbox narrower than its
        // row) is tapped in its centre. A row is wide and the box sits at its
        // left, first line; `app.css` gives it 1.2rem with a 0.6rem gap, so the
        // text starts ~29 pt right of the box's edge: 22 pt left of the text
        // is inside the box.
        let isBoxAlone = row.elementType != .staticText && frame.width < 60
        let point = isBoxAlone
            ? CGVector(dx: frame.midX - webView.frame.minX, dy: frame.midY - webView.frame.minY)
            : CGVector(dx: frame.minX - webView.frame.minX + (row.elementType == .staticText ? -22 : 12),
                       dy: frame.minY - webView.frame.minY + 12)
        origin.withOffset(point).tap()
        // Still on the form — a link that took the tap would leave it.
        let continueButton = webView.buttons.matching(NSPredicate(format: "label == 'Continue'")).firstMatch
        let end = Date().addingTimeInterval(5)
        while !(continueButton.exists && continueButton.isHittable), Date() < end { settle(0.3) }
        guard continueButton.exists, webView.staticTexts.matching(predicate).firstMatch.exists else {
            throw DevE2EError.flow("identity-login › ticking the Terms left the form (a link took the tap)")
        }
    }

    /// The 12 words of the phrase plate, in order. They sit between the
    /// plate's lead text and its warning; numbers are hidden from AX.
    private func readPhraseWords() throws -> [String] {
        let texts = try staticTexts(in: webView.snapshot())
        guard let top = texts.first(where: { $0.label.hasPrefix("Write these 12 words") })?.frame,
              let bottom = texts.first(where: { $0.label.hasPrefix("This is your only way to sign in") })?.frame else {
            throw DevE2EError.flow("the phrase plate is not on the page")
        }
        let words = texts
            .filter { $0.frame.minY > top.maxY && $0.frame.maxY < bottom.minY && $0.label.range(of: "^[a-z]+$", options: .regularExpression) != nil }
            .sorted { ($0.frame.minY.rounded(), $0.frame.minX) < ($1.frame.minY.rounded(), $1.frame.minX) }
            .map(\.label)
        guard words.count == 12 else {
            throw DevE2EError.flow("the phrase plate showed \(words.count) words, not 12")
        }
        return words
    }

    /// Swipes the web page until the element's frame is on screen.
    func revealInWeb(_ element: XCUIElement, _ what: String) throws {
        let bottom = webView.frame.height - 100
        for _ in 0..<6 where element.frame.maxY > bottom {
            webView.swipeUp()
            settle(0.7)
        }
        guard element.frame.maxY <= bottom, element.frame.minY > 100 else {
            throw DevE2EError.flow("\(what) could not be scrolled into reach")
        }
    }
    
    /// A tap on the element's frame: a styled checkbox's input has no
    /// activation point of its own, its label row takes the tap.
    func tapFrame(_ element: XCUIElement) {
        let frame = element.frame
        webView.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + min(24, frame.width / 2), dy: frame.midY))
            .tap()
    }
    
    private func staticTexts(in snapshot: XCUIElementSnapshot) throws -> [(label: String, frame: CGRect)] {
        elements(of: .staticText, in: snapshot)
    }

    private func elements(of type: XCUIElement.ElementType, in snapshot: XCUIElementSnapshot) -> [(label: String, frame: CGRect)] {
        var found: [(label: String, frame: CGRect)] = []
        var stack = [snapshot]
        while let node = stack.popLast() {
            if node.elementType == type, !node.label.isEmpty { found.append((node.label, node.frame)) }
            stack.append(contentsOf: node.children)
        }
        return found
    }
}
