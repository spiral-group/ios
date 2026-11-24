//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation
@testable import Spiral
import SwiftUI
import Synchronization
import Testing
import UIKit

@MainActor
struct NavigationTabCoordinatorTests {
    enum TestTab { case tab, chats, spaces }
    private var navigationTabCoordinator: NavigationTabCoordinator<TestTab>
    
    init() {
        navigationTabCoordinator = NavigationTabCoordinator()
    }
    
    @Test
    mutating func tabs() {
        #expect(navigationTabCoordinator.tabCoordinators.isEmpty)
        
        let someCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setTabs([.init(coordinator: someCoordinator, details: .init(tag: .tab, title: "Tab", icon: \.help, selectedIcon: \.helpSolid))])
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [someCoordinator])
        
        let chatsCoordinator = SomeTestCoordinator()
        let spacesCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setTabs([
            .init(coordinator: chatsCoordinator, details: .init(tag: .chats, title: "Chats", icon: \.chat, selectedIcon: \.chatSolid)),
            .init(coordinator: spacesCoordinator, details: .init(tag: .spaces, title: "Spaces", icon: \.space, selectedIcon: \.spaceSolid))
        ])
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [chatsCoordinator, spacesCoordinator])
    }
    
    // AGENT-PLATFORM (Brief 0083): a pass served from the cache must still depend on the avatar, or a new photo never redraws.
    @Test
    func aCachedAvatarStillRedrawsOnAChange() {
        let details = NavigationTabCoordinator<TestTab>.TabDetails(tag: .tab, title: "Settings", icon: \.userProfile, selectedIcon: \.userProfileSolid)
        details.avatar = SpiralTabAvatar(name: "Alice", contentID: "@alice:example.com")
        let render = { _ = details.iconView(for: .init(isSelected: false, colorScheme: .light, colorSchemeContrast: .standard, legibilityWeight: .regular, displayScale: 2)) }
        render()
        
        let didInvalidate = Mutex(false)
        withObservationTracking(render) {
            didInvalidate.withLock { $0 = true }
        }
        details.avatar = SpiralTabAvatar(name: "Bob", contentID: "@bob:example.com")
        
        #expect(didInvalidate.withLock { $0 })
    }
    
    // AGENT-PLATFORM (1.0.3): the pre-drawn images follow Bold Text and Increase Contrast, as the bar's own symbols do.
    @Test
    func boldTextAndIncreaseContrastRedrawTheTabImages() throws {
        let symbol = NavigationTabCoordinator<TestTab>.TabDetails(tag: .tab, title: "Chats", symbol: SpiralTabSymbol.chats)
        let avatar = NavigationTabCoordinator<TestTab>.TabDetails(tag: .tab, title: "Settings", icon: \.userProfile, selectedIcon: \.userProfileSolid)
        avatar.avatar = SpiralTabAvatar(name: "Alice", contentID: "@alice:example.com")
        
        for details in [symbol, avatar] {
            let standard = try pixels(of: details, contrast: .standard, weight: .regular)
            #expect(try pixels(of: details, contrast: .standard, weight: .bold) != standard, "\(details.title) ignores Bold Text")
            #expect(try pixels(of: details, contrast: .increased, weight: .regular) != standard, "\(details.title) ignores Increase Contrast")
        }
    }
    
    // AGENT-PLATFORM (coverage walk F3): VoiceOver and UI tests read the badge from the tab's value.
    @Test
    func aBadgeIsTheTabsAccessibilityValue() {
        let details = NavigationTabCoordinator<TestTab>.TabDetails(tag: .tab, title: "Agents", icon: \.host, selectedIcon: \.host)
        #expect(details.badgeAccessibilityValue == nil)
        
        details.badgeCount = 1
        #expect(details.badgeAccessibilityValue == "1 waiting")
        details.badgeCount = 3
        #expect(details.badgeAccessibilityValue == "3 waiting")
    }
    
    @Test
    mutating func singleSheet() {
        let tabCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setTabs([.init(coordinator: tabCoordinator, details: .init(tag: .tab, title: "Tab", icon: \.help, selectedIcon: \.helpSolid))])
        
        let coordinator = SomeTestCoordinator()
        navigationTabCoordinator.setSheetCoordinator(coordinator)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        assertCoordinatorsEqual(coordinator, navigationTabCoordinator.sheetCoordinator)
        
        navigationTabCoordinator.setSheetCoordinator(nil)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        #expect(navigationTabCoordinator.sheetCoordinator == nil)
    }
    
    @Test
    mutating func multipleSheets() {
        let tabCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setTabs([.init(coordinator: tabCoordinator, details: .init(tag: .tab, title: "Tab", icon: \.help, selectedIcon: \.helpSolid))])
        
        let sheetCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setSheetCoordinator(sheetCoordinator)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        assertCoordinatorsEqual(sheetCoordinator, navigationTabCoordinator.sheetCoordinator)
        
        let someOtherSheetCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setSheetCoordinator(someOtherSheetCoordinator)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        assertCoordinatorsEqual(someOtherSheetCoordinator, navigationTabCoordinator.sheetCoordinator)
    }
    
    @Test
    mutating func fullScreenCover() {
        let tabCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setTabs([.init(coordinator: tabCoordinator, details: .init(tag: .tab, title: "Tab", icon: \.help, selectedIcon: \.helpSolid))])
        
        let coordinator = SomeTestCoordinator()
        navigationTabCoordinator.setFullScreenCoverCoordinator(coordinator)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        assertCoordinatorsEqual(coordinator, navigationTabCoordinator.fullScreenCoverCoordinator)
        
        navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        #expect(navigationTabCoordinator.fullScreenCoverCoordinator == nil)
    }
    
    /// AGENT-PLATFORM (1.0.3): whoever waits for a cover to be on screen (the sign-in's logo) is never left waiting
    /// on one that went before it appeared.
    @Test
    mutating func aCoverGoneBeforeItAppearedStillCallsBack() {
        var replacedCalls = 0
        // swiftlint:disable:next trailing_closure - a trailing closure would be taken as the dismissal callback
        navigationTabCoordinator.setFullScreenCoverCoordinator(SomeTestCoordinator(), presentationCallback: { replacedCalls += 1 })
        #expect(replacedCalls == 0, "Not yet on screen.")
        
        var removedCalls = 0
        // swiftlint:disable:next trailing_closure - a trailing closure would be taken as the dismissal callback
        navigationTabCoordinator.setFullScreenCoverCoordinator(SomeTestCoordinator(), presentationCallback: { removedCalls += 1 })
        #expect(replacedCalls == 1, "Replaced before it appeared.")
        #expect(removedCalls == 0, "The replacement is the one now waiting.")
        
        navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
        #expect(removedCalls == 1, "Removed before it appeared.")
        
        navigationTabCoordinator.setFullScreenCoverCoordinator(SomeTestCoordinator())
        navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
        #expect(replacedCalls == 1 && removedCalls == 1, "Each callback runs once.")
    }
    
    @Test
    mutating func overlay() {
        let tabCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setTabs([.init(coordinator: tabCoordinator, details: .init(tag: .tab, title: "Tab", icon: \.help, selectedIcon: \.helpSolid))])
        
        let overlayCoordinator = SomeTestCoordinator()
        navigationTabCoordinator.setOverlayCoordinator(overlayCoordinator)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        assertCoordinatorsEqual(overlayCoordinator, navigationTabCoordinator.overlayCoordinator)
        
        // The coordinator should still be retained when changing the presentation mode.
        navigationTabCoordinator.setOverlayPresentationMode(.minimized)
        assertCoordinatorsEqual(overlayCoordinator, navigationTabCoordinator.overlayCoordinator)
        navigationTabCoordinator.setOverlayPresentationMode(.fullScreen)
        assertCoordinatorsEqual(overlayCoordinator, navigationTabCoordinator.overlayCoordinator)
        
        navigationTabCoordinator.setOverlayCoordinator(nil)
        
        assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [tabCoordinator])
        #expect(navigationTabCoordinator.overlayCoordinator == nil)
    }
    
    // MARK: - Dismissal Callbacks
    
    @Test
    mutating func tabDismissalCallbacks() async {
        let chatsCoordinator = SomeTestCoordinator()
        let spacesCoordinator = SomeTestCoordinator()
        
        await confirmation("Wait for callback", expectedCount: 2) { confirm in
            navigationTabCoordinator.setTabs([
                .init(coordinator: chatsCoordinator, details: .init(tag: .chats, title: "Chats", icon: \.chat, selectedIcon: \.chatSolid)) { confirm() },
                .init(coordinator: spacesCoordinator, details: .init(tag: .spaces, title: "Spaces", icon: \.space, selectedIcon: \.spaceSolid)) { confirm() }
            ])
            assertCoordinatorsEqual(navigationTabCoordinator.tabCoordinators, [chatsCoordinator, spacesCoordinator])
            
            navigationTabCoordinator.setTabs([.init(coordinator: SomeTestCoordinator(), details: .init(tag: .tab, title: "Tab", icon: \.help, selectedIcon: \.helpSolid))])
        }
    }
    
    @Test
    mutating func sheetDismissalCallback() async {
        let coordinator = SomeTestCoordinator()
        await confirmation("Wait for callback") { confirm in
            navigationTabCoordinator.setSheetCoordinator(coordinator) {
                confirm()
            }
            
            navigationTabCoordinator.setSheetCoordinator(nil)
        }
    }
    
    @Test
    mutating func fullScreenCoverDismissalCallback() async {
        let coordinator = SomeTestCoordinator()
        await confirmation("Wait for callback") { confirm in
            navigationTabCoordinator.setFullScreenCoverCoordinator(coordinator) {
                confirm()
            }
            
            navigationTabCoordinator.setFullScreenCoverCoordinator(nil)
        }
    }
    
    @Test
    mutating func overlayDismissalCallback() async {
        let overlayCoordinator = SomeTestCoordinator()
        
        await confirmation("Wait for callback") { confirm in
            navigationTabCoordinator.setOverlayCoordinator(overlayCoordinator) {
                confirm()
            }
            
            navigationTabCoordinator.setOverlayCoordinator(nil)
        }
    }
    
    @Test
    mutating func overlayDismissalCallbackWhenChangingMode() async {
        let overlayCoordinator = SomeTestCoordinator()
        
        await waitForConfirmation("Callback should not be called when just changing mode",
                                  expectedCount: 0,
                                  timeout: .seconds(1)) { confirmation in
            navigationTabCoordinator.setOverlayCoordinator(overlayCoordinator) {
                confirmation()
            }
            
            navigationTabCoordinator.setOverlayPresentationMode(.minimized)
        }
    }
    
    // MARK: - Private
    
    private func pixels(of details: NavigationTabCoordinator<TestTab>.TabDetails, contrast: ColorSchemeContrast, weight: LegibilityWeight) throws -> Data {
        let appearance = SpiralTabAvatar.Appearance(isSelected: true, colorScheme: .light, colorSchemeContrast: contrast, legibilityWeight: weight, displayScale: 2)
        let renderer = ImageRenderer(content: details.iconView(for: appearance))
        return try #require(renderer.uiImage?.pngData())
    }
    
    private func assertCoordinatorsEqual(_ lhs: CoordinatorProtocol?, _ rhs: CoordinatorProtocol?) {
        guard let lhs = lhs as? SomeTestCoordinator,
              let rhs = rhs as? SomeTestCoordinator else {
            Issue.record("Coordinators are not the same")
            return
        }
        
        #expect(lhs.id == rhs.id)
    }
    
    private func assertCoordinatorsEqual(_ lhs: [CoordinatorProtocol], _ rhs: [CoordinatorProtocol]) {
        guard lhs.count == rhs.count else {
            Issue.record("Coordinators are not the same")
            return
        }
        
        for (index, coordinator) in lhs.enumerated() {
            assertCoordinatorsEqual(coordinator, rhs[index])
        }
    }
}

// MARK: - 1.0.3: a screen over a focused field takes the keyboard

/// AGENT-PLATFORM (1.0.3, operator 2026-11-21): the keyboard stayed over the call screen when going back to the call from
/// a chat being typed in. A real field in a real window has focus; each presentation must take it away.
@MainActor
struct NavigationKeyboardDismissalTests {
    enum TestTab { case chats, spaces }

    @Test
    func theCallComingFullScreenTakesTheKeyboard() throws {
        let tabs = NavigationTabCoordinator<TestTab>()
        tabs.setOverlayCoordinator(SomeTestCoordinator(), presentationMode: .minimized)
        let (window, field) = try focusedField()
        defer { window.isHidden = true }

        // The same mode again (the PiP window starting while already on the bar) leaves typing alone.
        tabs.setOverlayPresentationMode(.minimized)
        #expect(field.isFirstResponder)

        tabs.setOverlayPresentationMode(.fullScreen)
        #expect(!field.isFirstResponder)
    }

    @Test
    func aNewCallScreenTakesTheKeyboard() throws {
        let tabs = NavigationTabCoordinator<TestTab>()
        let (window, field) = try focusedField()
        defer { window.isHidden = true }

        tabs.setOverlayCoordinator(SomeTestCoordinator())

        #expect(!field.isFirstResponder)
    }

    @Test
    func aSheetOrACoverTakesTheKeyboard() throws {
        // A fresh coordinator each: a modal left up by the previous one would rightly keep the next from taking it.
        for present in [{ NavigationTabCoordinator<TestTab>().setSheetCoordinator(SomeTestCoordinator()) },
                        { NavigationTabCoordinator<TestTab>().setFullScreenCoverCoordinator(SomeTestCoordinator()) },
                        { NavigationStackCoordinator().setSheetCoordinator(SomeTestCoordinator()) },
                        { NavigationStackCoordinator().setFullScreenCoverCoordinator(SomeTestCoordinator()) }] {
            let (window, field) = try focusedField()
            present()
            #expect(!field.isFirstResponder)
            window.isHidden = true
        }
    }

    /// Review finding: going to the bar with a field in the call focused takes the keyboard too.
    @Test
    func theCallGoingToItsBarTakesTheKeyboard() throws {
        let tabs = NavigationTabCoordinator<TestTab>()
        tabs.setOverlayCoordinator(SomeTestCoordinator(), presentationMode: .fullScreen)
        let (window, field) = try focusedField()
        defer { window.isHidden = true }

        tabs.setOverlayPresentationMode(.minimized)

        #expect(!field.isFirstResponder)
    }

    /// Review finding: a sheet the call spares stays above it, so typing in it goes on when a call comes.
    @Test
    func aCallUnderASparedSheetLeavesItsFieldAlone() throws {
        let tabs = NavigationTabCoordinator<TestTab>()
        tabs.setSheetCoordinator(SomeTestCoordinator())
        let (window, field) = try focusedField()
        defer { window.isHidden = true }

        tabs.setOverlayCoordinator(SomeTestCoordinator())
        #expect(field.isFirstResponder)
        tabs.setFullScreenCoverCoordinator(SomeTestCoordinator())
        #expect(field.isFirstResponder)
    }

    /// Follow-up review: a tab-level sheet (a verification request) can't show over a tab's own sheet being typed in.
    @Test
    func aSheetThatCantShowLeavesTheFieldUnderneathAlone() throws {
        let tabs = NavigationTabCoordinator<TestTab>()
        let split = NavigationSplitCoordinator(placeholderCoordinator: SomeTestCoordinator())
        tabs.setTabs([.init(coordinator: split, details: .init(tag: .chats, title: "Chats", icon: \.chat, selectedIcon: \.chatSolid))])
        split.setSheetCoordinator(SomeTestCoordinator())
        let (window, field) = try focusedField()
        defer { window.isHidden = true }

        tabs.setSheetCoordinator(SomeTestCoordinator())

        #expect(field.isFirstResponder)
    }

    @Test
    func aSplitsSheetOrCoverTakesTheKeyboard() throws {
        let split = NavigationSplitCoordinator(placeholderCoordinator: SomeTestCoordinator())
        for present in [{ split.setSheetCoordinator(SomeTestCoordinator()) }, { split.setFullScreenCoverCoordinator(SomeTestCoordinator()) }] {
            let (window, field) = try focusedField()
            present()
            #expect(!field.isFirstResponder)
            window.isHidden = true
        }
    }

    @Test
    func switchingTabsTakesTheKeyboard() throws {
        let tabs = NavigationTabCoordinator<TestTab>()
        tabs.setTabs([.init(coordinator: SomeTestCoordinator(), details: .init(tag: .chats, title: "Chats", icon: \.chat, selectedIcon: \.chatSolid)),
                      .init(coordinator: SomeTestCoordinator(), details: .init(tag: .spaces, title: "Spaces", icon: \.space, selectedIcon: \.spaceSolid))])
        let (window, field) = try focusedField()
        defer { window.isHidden = true }

        tabs.selectedTab = .chats
        #expect(field.isFirstResponder)

        tabs.selectedTab = .spaces
        #expect(!field.isFirstResponder)
    }

    /// A field with focus in a window of its own; `close` hides it and gives the key back to the window that had it, so
    /// other suites holding a key window aren't disturbed.
    private func focusedField() throws -> (FocusedWindow, UITextField) {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        window.addSubview(field)
        window.makeKeyAndVisible()
        field.becomeFirstResponder()
        try #require(field.isFirstResponder)
        return (FocusedWindow(window: window, previousKey: previousKey), field)
    }

    struct FocusedWindow {
        let window: UIWindow
        let previousKey: UIWindow?

        var isHidden: Bool {
            get { window.isHidden }
            nonmutating set {
                window.isHidden = newValue
                if newValue { previousKey?.makeKey() }
            }
        }
    }
}

/// AGENT-PLATFORM (DEBT, 1.0.3): the Settings tab's avatar over the person's profile updates.
@MainActor
struct SpiralTabAvatarUpdateTests {
    private let photoURL = URL.mockMXCAvatar
    private let otherURL = URL.mockMXCImage

    /// A profile update with the same photo keeps the one drawn: it used to flash to the monogram on every one.
    @Test
    func theSamePhotoStaysThroughAProfileUpdate() {
        let photo = UIImage()
        let drawn = SpiralTabAvatar(name: "Alice", contentID: "@alice:spiral.md", photo: photo)

        let renamed = SpiralTabAvatar.updated(drawn, photoURL: photoURL, name: "Alice K", contentID: "@alice:spiral.md", newPhotoURL: photoURL)
        #expect(renamed.avatar.photo === photo)
        #expect(renamed.avatar.name == "Alice K")
        #expect(!renamed.loadsPhoto)
    }

    @Test
    func aNewPhotoLoadsAndNoneIsTheMonogram() {
        let drawn = SpiralTabAvatar(name: "Alice", contentID: "@alice:spiral.md", photo: UIImage())

        let changed = SpiralTabAvatar.updated(drawn, photoURL: photoURL, name: "Alice", contentID: "@alice:spiral.md", newPhotoURL: otherURL)
        #expect(changed.avatar.photo == nil)
        #expect(changed.loadsPhoto)

        let removed = SpiralTabAvatar.updated(drawn, photoURL: photoURL, name: "Alice", contentID: "@alice:spiral.md", newPhotoURL: nil)
        #expect(removed.avatar.photo == nil)
        #expect(!removed.loadsPhoto)

        let first = SpiralTabAvatar.updated(nil, photoURL: nil, name: "Alice", contentID: "@alice:spiral.md", newPhotoURL: photoURL)
        #expect(first.loadsPhoto)
    }

    /// A photo that failed to load is tried again on the next update with the same URL; once drawn, the same URL keeps
    /// it and tells nothing.
    @Test
    func aFailedLoadIsTriedAgainAndADrawnPhotoStays() async throws {
        let photo = UIImage()
        var loads = 0
        var fails = true
        var told = 0
        let loader = SpiralTabAvatarLoader { _ in
            loads += 1
            return fails ? nil : photo
        } onChange: { _ in
            told += 1
        }

        loader.update(name: "Alice", contentID: "@alice:spiral.md", photoURL: photoURL)
        try await Self.waitUntil { loads == 1 }
        try await Task.sleep(for: .milliseconds(20))
        #expect(loader.avatar?.photo == nil)

        fails = false
        loader.update(name: "Alice", contentID: "@alice:spiral.md", photoURL: photoURL)
        try await Self.waitUntil { loader.avatar?.photo != nil }
        #expect(loads == 2)
        #expect(loader.avatar?.photo === photo)

        let toldBefore = told
        loader.update(name: "Alice", contentID: "@alice:spiral.md", photoURL: photoURL)
        #expect(loads == 2)
        #expect(told == toldBefore, "the same profile again changes nothing on the tab")
    }

    private static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

private class SomeTestCoordinator: CoordinatorProtocol {
    let id = UUID()
}
