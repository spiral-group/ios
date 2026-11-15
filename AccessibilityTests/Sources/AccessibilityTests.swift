//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//

import XCTest

@MainActor
final class AccessibilityTests: XCTestCase {
    var app: XCUIApplication!
    
    func performAccessibilityAudit(named name: String) async throws {
        // AGENT-PLATFORM (Brief 0083 L1c): a SpiralGatedPreview gets Spiral's stricter audit, in light and in dark.
        for audit in Self.audits(forPreviewNamed: name) {
            try await performAccessibilityAudit(named: name, audit: audit)
        }
    }
    
    private func performAccessibilityAudit(named name: String, audit: Audit) async throws {
        defer { Self.failForMustFailStatesNotChecked(inPreviewNamed: name, appearance: audit.appearance) } // AGENT-PLATFORM (Brief 0083): after a throw too.
        let client = try UITestsSignalling.Client(mode: .tests)
        app = Application.launch(viewID: name, appearance: audit.appearance) // AGENT-PLATFORM (Brief 0083 L1c)
        await client.waitForApp()
        defer { try? client.stop() }
        
        try client.send(.accessibilityAudit(.nextPreview))
        
        // To handle location sharing popup in CI
        allowLocationPermissions()
        var barFrames = BarFrames() // AGENT-PLATFORM (Brief 0083): what the state's bars hold, to compare with what the app hides.
        forLoop: for await signal in client.signals.values {
            switch signal {
            case .accessibilityAudit(let auditSignal):
                switch auditSignal {
                case .nextPreviewReady(let name):
                    // AGENT-PLATFORM (Brief 0083): Spiral's contrast issues wait for a second audit, once the app has left out the gate's exemptions.
                    let outcome = Self.expectingFailure(ofStateNamed: name, in: audit) {
                        performAccessibilityAuditForPreview(named: name, audit: audit)
                    }
                    barFrames = outcome.barFrames
                    try client.send(.accessibilityAudit(outcome.heldContrastBack ? .prepareContrastAudit : .nextPreview))
                case .contrastAuditReady(let name, let hiddenElements): // AGENT-PLATFORM (Brief 0083)
                    Self.failForHiddenElementsOutsideBars(hiddenElements, barFrames: barFrames.all, stateNamed: audit.activityName(forPreviewNamed: name))
                    var recheck = audit.contrastRecheck
                    recheck.headerBottom = barFrames.headerBottom
                    _ = Self.expectingFailure(ofStateNamed: name, in: recheck) {
                        performAccessibilityAuditForPreview(named: name, audit: recheck)
                    }
                    try client.send(.accessibilityAudit(.nextPreview))
                case .noMorePreviews:
                    break forLoop
                default:
                    XCTFail("Unhandled signal")
                }
            default:
                XCTFail("Unhandled signal")
            }
        }
        
        app.terminate()
    }
    
    private func allowLocationPermissions() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notificationAlertAllowButton = springboard.buttons["Allow While Using App"].firstMatch
        if notificationAlertAllowButton.exists {
            notificationAlertAllowButton.tap()
        }
    }
    
    /// - Returns: What the contrast recheck needs from this audit. AGENT-PLATFORM (Brief 0083)
    private func performAccessibilityAuditForPreview(named name: String, audit: Audit) -> AuditOutcome { // AGENT-PLATFORM (Brief 0083)
        // Alows us to log the name of the preview that is being tested
        XCTContext.runActivity(named: audit.activityName(forPreviewNamed: name)) { _ in // AGENT-PLATFORM (Brief 0083 L1c)
            // Previews that focus a text field bring up the system keyboard, which we can't fix.
            // Snapshot the keyboard in one query so one that's dismissing can't fail the test between checking and reading it.
            // AGENT-PLATFORM (Brief 0083): check first, which doesn't wait (a snapshot of no keyboard retries for 2 s), and only at
            // the first issue that has an element: the audit has run by then, so a keyboard that focus raised late is up.
            let keyboard = app.keyboards.firstMatch
            lazy var keyboardFrame = keyboard.exists ? (try? keyboard.snapshot().frame) ?? .null : .null
            var outcome = AuditOutcome() // AGENT-PLATFORM (Brief 0083)
            
            do {
                // We have removed `textClipped` and `contrast` for now
                // AGENT-PLATFORM (Brief 0083 L1c): Spiral's audit has them back (SpiralAccessibilityGates.swift).
                try app.performAccessibilityAudit(for: audit.types) { issue in
                    // AGENT-PLATFORM (Brief 0083): a colour emoji's own colours and text a list has scrolled out of sight aren't
                    // text contrast (contrast triage H and I), in whichever audit names the issue's element; and a known
                    // failure's description on another element fails on its own.
                    if Self.isExemptContrastIssue(issue, in: self.app, previewNamed: audit.activityName(forPreviewNamed: name), headerBottom: audit.headerBottom,
                                                  readsOwnPixels: audit.isContrastRecheck)
                        || Self.isKnownFailureElsewhere(issue, previewNamed: name, in: audit) {
                        return true
                    }
                    
                    // AGENT-PLATFORM (Brief 0083): only the recheck's contrast issues count.
                    if audit.defersContrast, issue.auditType == .contrast {
                        Self.reportHeldContrastIssue(issue, previewNamed: audit.activityName(forPreviewNamed: name))
                        outcome.heldContrastBack = true
                        return true
                    }
                    
                    // Specific tests do not need specific accessibilty audit types
                    if Self.ignoredA11yTest[name]?.isAccessibilityIssueFiltered(issue) == true {
                        return true
                    }
                    
                    // Remove false positives for null elements
                    guard let element = issue.element else {
                        // AGENT-PLATFORM (Brief 0083 L1c): except Spiral's contrast and clipping issues, which SwiftUI text reports on a bare node.
                        return !Self.reportsIssueWithoutElement(issue, previewNamed: audit.activityName(forPreviewNamed: name))
                    }
                    
                    // The system keyboard's own elements aren't ours to fix
                    if keyboardFrame.contains(element.frame) {
                        return true
                    }
                    
                    // We are fine with elements that only partially support dynamic types
                    guard issue.compactDescription != Self.partiallyUnsupportedDynamicTypeMessage else {
                        return true
                    }
                    
                    // We can filter out matrix entities from the non human-readable error
                    if issue.compactDescription == Self.notHumanReadableMessage, Self.isMatrixIdentifier(element.label) {
                        return true
                    }
                    
                    // Additional filters for specific elements that lead to false positives or neglectable issues.
                    if Self.ignoredA11yIdentifiers[element.identifier]?.isAccessibilityIssueFiltered(issue) == true {
                        return true
                    }
                    
                    // swiftlint:disable:next print_deprecation
                    print("🔍 A11Y ISSUE [\(audit.activityName(forPreviewNamed: name))] type=\(issue.auditType) desc=\(issue.compactDescription) element=\(issue.element?.debugDescription ?? "nil")") // AGENT-PLATFORM (Brief 0083 L1c)
                    
                    return false
                }
            } catch {
                XCTFail("Failed to perform the accessibility audit: \(error)")
            }
            // AGENT-PLATFORM (Brief 0083): the bars, which the recheck can't see on iOS 26+, by their pixels.
            if audit.defersContrast {
                outcome.barFrames = checkBarContrast(stateNamed: audit.activityName(forPreviewNamed: name)) { keyboardFrame }
            }
            return outcome // AGENT-PLATFORM (Brief 0083)
        }
    }
    
    private static func isMatrixIdentifier(_ string: String) -> Bool {
        MatrixEntityRegex.isMatrixRoomAlias(string) || MatrixEntityRegex.isMatrixUserIdentifier(string) || string == PillUtilities.atRoom || MatrixEntityRegex.isLegacyMatrixRoomID(string)
    }
    
    private static let partiallyUnsupportedDynamicTypeMessage = "Dynamic Type font sizes are partially unsupported"
    private static let notHumanReadableMessage = "Label not human-readable"
    
    /// Use this array to filter add specific filters to ignore specific issues for certain elements
    private static let ignoredA11yIdentifiers: [String: [FilterType]] = [
        A11yIdentifiers.serverConfirmationScreen.serverPicker: [.compactDescription(notHumanReadableMessage)]
    ]
    
    /// Use this array to filter add specific filters to ignore specific tests
    private static let ignoredA11yTest: [String: [FilterType]] = [
        // It's an image rendering test doesn't need to have descriptions
        "RoomAvatarImage_Previews-0": [.auditType(.sufficientElementDescription)]
    ]
}

private enum FilterType {
    /// Filter by the content of the compactDescription of the issue
    case compactDescription(String)
    /// Filter by the type of the issue
    case auditType(XCUIAccessibilityAuditType)
}

@MainActor
private extension Array where Element == FilterType {
    func isAccessibilityIssueFiltered(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        for filter in self {
            switch filter {
            case .auditType(issue.auditType):
                return true
            case .compactDescription(issue.compactDescription):
                return true
            default:
                break
            }
        }
        return false
    }
}
