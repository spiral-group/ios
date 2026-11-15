//
// Copyright 2025 Element Creations Ltd.
// Copyright 2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// Class responsible for displaying an arbitrary number of coordinators within the tab bar.
@Observable class NavigationTabCoordinator<Tag: Hashable>: CoordinatorProtocol, CustomStringConvertible {
    struct Tab {
        let coordinator: CoordinatorProtocol
        let details: TabDetails
        var dismissalCallback: (() -> Void)?
    }
    
    @Observable class TabDetails {
        /// A unique tab that identifies the tab for selection.
        let tag: Tag
        let title: String
        /// AGENT-PLATFORM (Brief 0083, decision 386): a Compound icon with its selected form, or one of Spiral's own
        /// symbols, which the tab bar sizes and tints as it does the system's.
        enum Glyph {
            case compound(icon: KeyPath<CompoundIcons, Image>, selectedIcon: KeyPath<CompoundIcons, Image>)
            case symbol(String)
        }

        let glyph: Glyph
        // AGENT-PLATFORM (Brief 0083, question 343): the person's tab draws their avatar in place of the glyph.
        var avatar: SpiralTabAvatar? {
            didSet { avatarImages = [:] }
        }
        
        /// The images rendered so far: a tab's label is rebuilt on every update, and a renderer is slow.
        @ObservationIgnored private var avatarImages = [SpiralTabAvatar.Appearance: UIImage]()
        /// The symbol drawn so far, per appearance (decision 386).
        @ObservationIgnored private var symbolImages = [SpiralTabAvatar.Appearance: UIImage]()
        let accessibilityIdentifier: String?
        var badgeCount = 0
        
        // AGENT-PLATFORM (coverage walk F3): the badge itself is not in the accessibility
        // tree; the tab's value carries the count for VoiceOver and UI tests.
        var badgeAccessibilityValue: String? {
            badgeCount > 0 ? UntranslatedL10n.a11yTabBadgeCount(badgeCount) : nil
        }
        
        /// Provide the tab's split coordinator in here to have the tab bar automatically hidden
        /// when pushing a child into the split view's details on iPhone/compact iPad.
        weak var navigationSplitCoordinator: NavigationSplitCoordinator?
        
        init(tag: Tag, title: String, icon: KeyPath<CompoundIcons, Image>, selectedIcon: KeyPath<CompoundIcons, Image>, accessibilityIdentifier: String? = nil) {
            self.tag = tag
            self.title = title
            glyph = .compound(icon: icon, selectedIcon: selectedIcon)
            self.accessibilityIdentifier = accessibilityIdentifier
        }

        init(tag: Tag, title: String, symbol: String, accessibilityIdentifier: String? = nil) {
            self.tag = tag
            self.title = title
            glyph = .symbol(symbol)
            self.accessibilityIdentifier = accessibilityIdentifier
        }
        
        // AGENT-PLATFORM (Brief 0083, question 343): a tab bar takes an image, so the avatar comes as one in its own colours.
        @MainActor @ViewBuilder
        func iconView(isSelected: Bool, colorScheme: ColorScheme, displayScale: CGFloat) -> some View {
            if let image = avatarImage(for: .init(isSelected: isSelected, colorScheme: colorScheme, displayScale: displayScale)) {
                Image(uiImage: image)
                    .renderingMode(.original)
            } else {
                switch glyph {
                case .compound(let icon, let selectedIcon):
                    CompoundIcon(isSelected ? selectedIcon : icon)
                case .symbol(let name):
                    // Decision 386: the bar redraws any symbol it is given as a one-colour template, which flattens
                    // its layers, so the symbol comes drawn: hierarchical, the lighter layer lighter, in the colour the
                    // bar gives that state.
                    if let image = symbolImage(named: name, for: .init(isSelected: isSelected, colorScheme: colorScheme, displayScale: displayScale)) {
                        Image(uiImage: image)
                            .renderingMode(.original)
                    }
                }
            }
        }
        
        /// The tab's symbol drawn hierarchically at the size the bar draws its symbols, in the bar's colours (`SpiralTabGlyph`).
        @MainActor
        private func symbolImage(named name: String, for appearance: SpiralTabAvatar.Appearance) -> UIImage? {
            if let image = symbolImages[appearance] {
                return image
            }
            let renderer = ImageRenderer(content: Image(name)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SpiralTabGlyph.color(isSelected: appearance.isSelected))
                .font(.system(size: Self.symbolPointSize, weight: .medium))
                .environment(\.colorScheme, appearance.colorScheme))
            renderer.scale = appearance.displayScale
            let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal)
            symbolImages[appearance] = image
            return image
        }

        /// The point size the bar draws its symbols at (measured on iOS 26: 20 pt).
        private static var symbolPointSize: CGFloat {
            20
        }

        @MainActor
        private func avatarImage(for appearance: SpiralTabAvatar.Appearance) -> UIImage? {
            // AGENT-PLATFORM (Brief 0083): read first, so a pass served from the cache still depends on the avatar.
            guard let avatar else { return nil }
            if let image = avatarImages[appearance] {
                return image
            }
            let image = avatar.image(for: appearance)
            avatarImages[appearance] = image
            return image
        }
        
        func barVisibility(in horizontalSizeClass: UserInterfaceSizeClass?) -> Visibility {
            if horizontalSizeClass == .compact, navigationSplitCoordinator?.detailCoordinator != nil {
                // Whilst we support pushing screens on the stack in the sidebarCoordinator, in practice
                // we never do that, so simply checking that the detailCoordinator exists is enough.
                .hidden
            } else {
                .automatic
            }
        }
    }
    
    // MARK: Tabs
    
    fileprivate struct TabModule: Identifiable {
        let module: NavigationModule
        let details: TabDetails
        
        var id: ObjectIdentifier {
            module.id
        }
        
        var coordinator: CoordinatorProtocol? {
            module.coordinator
        }
    }
    
    fileprivate var tabModules = [TabModule]() {
        didSet {
            let diffs = tabModules.map(\.module).difference(from: oldValue.map(\.module))
            diffs.forEach { change in
                switch change {
                case .insert(_, let module, _):
                    logPresentationChange("Set tab", module)
                    module.coordinator?.start()
                case .remove(_, let module, _):
                    logPresentationChange("Remove tab", module)
                    module.tearDown()
                }
            }
        }
    }
    
    /// The current set of coordinators displayed by the tabs.
    var tabCoordinators: [any CoordinatorProtocol] {
        tabModules.compactMap(\.module.coordinator)
    }
    
    /// AGENT-PLATFORM (decision 301): the tabs' tags in display order; the bar and the iPad rail both draw `tabModules`.
    var tabTags: [Tag] {
        tabModules.map(\.details.tag)
    }
    
    /// Updates the displayed tabs with the provided array.
    func setTabs(_ tabs: [Tab], animated: Bool = true) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            tabModules = tabs.map { TabModule(module: .init($0.coordinator, dismissalCallback: $0.dismissalCallback), details: $0.details) }
        }
        
        selectedTab = tabModules.first?.details.tag
    }
    
    /// The currently selected tab's tag.
    var selectedTab: Tag?
    
    // MARK: Sheets
    
    fileprivate var sheetModule: NavigationModule? {
        didSet {
            if let oldValue {
                logPresentationChange("Remove sheet", oldValue)
                oldValue.tearDown()
            }
            
            if let sheetModule {
                logPresentationChange("Set sheet", sheetModule)
                sheetModule.coordinator?.start()
            }
        }
    }
    
    var presentationDetents: Set<PresentationDetent> = []
    
    /// The currently presented sheet coordinator.
    var sheetCoordinator: (any CoordinatorProtocol)? {
        sheetModule?.coordinator
    }
    
    /// Present a sheet on top of the stack. If this NavigationStackCoordinator is embedded within a NavigationSplitCoordinator
    /// then the presentation will be proxied to the split
    /// - Parameters:
    ///   - coordinator: the coordinator to display
    ///   - animated: whether to animate the transition or not. Default is true
    ///   - dismissalCallback: called when the sheet has been dismissed, programatically or otherwise
    func setSheetCoordinator(_ coordinator: (any CoordinatorProtocol)?, animated: Bool = true, dismissalCallback: (() -> Void)? = nil) {
        guard let coordinator else {
            sheetModule = nil
            return
        }
        
        if sheetModule?.coordinator === coordinator {
            fatalError("Cannot use the same coordinator more than once")
        }
        
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            sheetModule = NavigationModule(coordinator, dismissalCallback: dismissalCallback)
        }
    }
    
    // MARK: Full Screen Cover
    
    fileprivate var fullScreenCoverModule: NavigationModule? {
        didSet {
            if let oldValue {
                logPresentationChange("Remove fullscreen cover", oldValue)
                oldValue.tearDown()
            }
            
            if let fullScreenCoverModule {
                logPresentationChange("Set fullscreen cover", fullScreenCoverModule)
                fullScreenCoverModule.coordinator?.start()
            }
        }
    }
    
    /// The currently presented fullscreen cover coordinator
    /// Fullscreen covers will be presented through the NavigationSplitCoordinator if provided
    var fullScreenCoverCoordinator: (any CoordinatorProtocol)? {
        fullScreenCoverModule?.coordinator
    }
    
    /// Present a fullscreen cover on top of the stack. If this NavigationStackCoordinator is embedded within a NavigationSplitCoordinator
    /// then the presentation will be proxied to the split
    /// - Parameters:
    ///   - coordinator: the coordinator to display
    ///   - animated: whether to animate the transition or not. Default is true
    ///   - dismissalCallback: called when the fullscreen cover has been dismissed, programatically or otherwise
    func setFullScreenCoverCoordinator(_ coordinator: (any CoordinatorProtocol)?, animated: Bool = true, dismissalCallback: (() -> Void)? = nil) {
        guard let coordinator else {
            fullScreenCoverModule = nil
            return
        }
        
        if fullScreenCoverModule?.coordinator === coordinator {
            fatalError("Cannot use the same coordinator more than once")
        }
        
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            fullScreenCoverModule = NavigationModule(coordinator, dismissalCallback: dismissalCallback)
        }
    }
    
    // MARK: - Overlay
    
    fileprivate var overlayModule: NavigationModule? {
        didSet {
            if let oldValue {
                logPresentationChange("Remove overlay", oldValue)
                oldValue.tearDown()
            }
            
            if let overlayModule {
                logPresentationChange("Set overlay", overlayModule)
                overlayModule.coordinator?.start()
            }
        }
    }
    
    /// The currently displayed overlay coordinator
    var overlayCoordinator: (any CoordinatorProtocol)? {
        overlayModule?.coordinator
    }
    
    enum OverlayPresentationMode { case fullScreen, minimized }
    // AGENT-PLATFORM: readable, so a test can see a call route return to its screen.
    fileprivate(set) var overlayPresentationMode: OverlayPresentationMode = .minimized
    
    /// Present an overlay on top of the tab view
    /// - Parameters:
    ///   - coordinator: the coordinator to display
    ///   - presentationMode: how the coordinator should be presented
    ///   - animated: whether the transition should be animated
    ///   - dismissalCallback: called when the overlay has been dismissed, programatically or otherwise
    func setOverlayCoordinator(_ coordinator: (any CoordinatorProtocol)?,
                               presentationMode: OverlayPresentationMode = .fullScreen,
                               animated: Bool = true,
                               dismissalCallback: (() -> Void)? = nil) {
        guard let coordinator else {
            overlayModule = nil
            return
        }
        
        if overlayModule?.coordinator === coordinator {
            fatalError("Cannot use the same coordinator more than once")
        }
        
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            overlayPresentationMode = presentationMode
            overlayModule = NavigationModule(coordinator, dismissalCallback: dismissalCallback)
        }
    }
    
    /// Updates the presentation of the overlay coordinator.
    /// - Parameters:
    ///   - mode: The type of presentation to use.
    ///   - animated: whether the transition should be animated
    func setOverlayPresentationMode(_ mode: OverlayPresentationMode, animated: Bool = true) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            overlayPresentationMode = mode
        }
    }
    
    // AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): the overlay is drawn on the tab view, so every
    // sheet and cover (this coordinator's, and its tabs' splits' and stacks') sits above it. A call closes
    // the ones its owner lets go (the operator: the call wins); `spare` keeps the rest. A sheet's own
    // sheets go with it.
    enum OverlayCoveringModal { case sheet, fullScreenCover }
    
    /// Dismisses the sheets and fullscreen covers presented over the tab view that `spare` doesn't keep, through
    /// the same teardown as a swipe.
    /// - Parameters:
    ///   - spare: true for a modal that must stay above the overlay.
    ///   - animated: whether the dismissals are animated.
    func dismissModalsCoveringTheOverlay(sparing spare: (any CoordinatorProtocol, OverlayCoveringModal) -> Bool,
                                         animated: Bool = true) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            if let sheetCoordinator, !spare(sheetCoordinator, .sheet) {
                sheetModule = nil
            }
            if let fullScreenCoverCoordinator, !spare(fullScreenCoverCoordinator, .fullScreenCover) {
                fullScreenCoverModule = nil
            }
            for coordinator in tabCoordinators {
                switch coordinator {
                case let split as NavigationSplitCoordinator:
                    if let sheet = split.sheetCoordinator, !spare(sheet, .sheet) { split.setSheetCoordinator(nil) }
                    if let cover = split.fullScreenCoverCoordinator, !spare(cover, .fullScreenCover) { split.setFullScreenCoverCoordinator(nil) }
                case let stack as NavigationStackCoordinator:
                    if let sheet = stack.sheetCoordinator, !spare(sheet, .sheet) { stack.setSheetCoordinator(nil) }
                    if let cover = stack.fullScreenCoverCoordinator, !spare(cover, .fullScreenCover) { stack.setFullScreenCoverCoordinator(nil) }
                default:
                    break
                }
            }
        }
    }
    
    /// Whether a modal shows a screen marked ``HoldsItsModalAboveACall``, anywhere in it or in the modals it
    /// presents itself. A stack's own `isInteractiveDismissDisabled` doesn't count: the post catalogue sets it
    /// against a gesture clash inside a post (question 412), not to keep anything, and a call closes it.
    static func modalRefusesToBeClosedByACall(_ coordinator: any CoordinatorProtocol) -> Bool {
        switch coordinator {
        case is HoldsItsModalAboveACall:
            return true
        case let stack as NavigationStackCoordinator:
            let shown = [stack.rootCoordinator, stack.sheetCoordinator, stack.fullScreenCoverCoordinator].compactMap(\.self) + stack.stackCoordinators
            return shown.contains { modalRefusesToBeClosedByACall($0) }
        case let split as NavigationSplitCoordinator:
            let shown = [split.sidebarCoordinator, split.detailCoordinator, split.sheetCoordinator, split.fullScreenCoverCoordinator].compactMap(\.self)
            return shown.contains { modalRefusesToBeClosedByACall($0) }
        default:
            return false
        }
    }
    
    // MARK: - CoordinatorProtocol

    /// No idea if this is particuarly needed for the TabView but we do this for the NavigationStackCoordinator and NavigationSplitCoordinator so it
    /// doesn't seem to harm to also do it here.
    func stop() {
        tabModules.forEach { $0.module.tearDown() }
    }
    
    func toPresentable() -> AnyView {
        AnyView(NavigationTabCoordinatorView(navigationTabCoordinator: self))
    }
    
    // MARK: - CustomStringConvertible
    
    var description: String {
        guard !tabModules.isEmpty else { return "NavigationTabCoordinator(Empty)" }
        return "NavigationTabCoordinator(\(tabCoordinators)"
    }
    
    // MARK: - Private
    
    private func logPresentationChange(_ change: String, _ module: NavigationModule) {
        if let coordinator = module.coordinator {
            MXLog.info("\(self) \(change): \(coordinator)")
        }
    }
}

extension EnvironmentValues {
    /// The horizontal size class of the ``NavigationTabCoordinatorView`` that contains this view.
    /// This provides a stable value regardless of whether the ``TabRailView`` is in the layout hierarchy.
    ///
    /// The rail consumes width and can cause a layout loop with the ``NavigationSplitCoordinatorView``
    /// when the split becomes compact, hides the rail but then has enough space to become regular and so
    /// attempts to show the rail etc.
    @Entry var tabViewHorizontalSizeClass: UserInterfaceSizeClass?

    // AGENT-PLATFORM (Brief 0063, native call UI G9): whether the overlay is
    // currently minimized. A self-minimizing overlay reads it to render its
    // compact bar instead of being hidden entirely.
    @Entry var isOverlayMinimized = false
}

// AGENT-PLATFORM (Brief 0063, native call UI G9): an overlay coordinator that
// renders its own minimized representation — a call bar — instead of being
// faded out. Hiding a native call entirely would also hide a running
// recording, which is a disclosure regression, not a cosmetic one.
protocol SelfMinimizingOverlayCoordinator: CoordinatorProtocol { }

// AGENT-PLATFORM (1.0.2, DEBT "a call under the sheet"): a screen its person can't swipe away (a recovery key
// to note down, a PIN being set, a device-owner check holding a continuation). A call doesn't close the modal
// that shows it; the call stays under it, as a gate wins over a call.
protocol HoldsItsModalAboveACall: CoordinatorProtocol { }

private struct NavigationTabCoordinatorView<Tag: Hashable>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme // AGENT-PLATFORM (Brief 0083, question 343)
    @Environment(\.displayScale) private var displayScale // AGENT-PLATFORM (Brief 0083, question 343)
    
    @Bindable var navigationTabCoordinator: NavigationTabCoordinator<Tag>
    
    @State private var standardAppearance = UITabBarAppearance()
    @State private var window: UIWindow?
    @State private var isFullScreen = true
    @State private var railBackgroundColor: Color = .compound.bgCanvasDefault
    
    var body: some View {
        // AGENT-PLATFORM (Brief 0063, G9): the minimized call bar is a
        // physical SIBLING of the app, stacked above it, so the app is
        // literally shorter while a call is minimized.
        //
        // A `.safeAreaInset` here was not enough. The tabs host SwiftUI
        // `NavigationStack`s, which are backed by `UINavigationController`s,
        // and a navigation bar positions itself from the WINDOW's safe area —
        // not from a SwiftUI inset applied outside it. So the app laid out
        // below the bar while the room's own navigation bar kept drawing at
        // the top, underneath the green (found on a device, and again after
        // the inset "fix"). Shrinking the container is the only version of
        // this that a nested navigation controller cannot ignore.
        VStack(spacing: 0) {
            minimizedOverlayBar

            appContent
        }
    }

    /// The bar a self-minimizing overlay draws for itself. Kept separate from
    /// the app content so the two are siblings in one stack rather than one
    /// being an inset or an overlay on the other.
    @ViewBuilder
    private var minimizedOverlayBar: some View {
        if let coordinator = navigationTabCoordinator.overlayModule?.coordinator,
           navigationTabCoordinator.overlayPresentationMode == .minimized,
           coordinator is SelfMinimizingOverlayCoordinator {
            coordinator.toPresentable()
                .environment(\.isOverlayMinimized, true)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var appContent: some View {
        tabView
            .environment(\.tabViewHorizontalSizeClass, horizontalSizeClass)
            .sheet(item: $navigationTabCoordinator.sheetModule) { module in
                module.coordinator?.toPresentable()
                    .id(module.id)
            }
            .fullScreenCover(item: $navigationTabCoordinator.fullScreenCoverModule) { module in
                module.coordinator?.toPresentable()
                    .id(module.id)
            }
            .accessibilityHidden(navigationTabCoordinator.overlayModule?.coordinator != nil && navigationTabCoordinator.overlayPresentationMode == .fullScreen)
            .overlay {
                Group {
                    if let coordinator = navigationTabCoordinator.overlayModule?.coordinator {
                        let isMinimized = navigationTabCoordinator.overlayPresentationMode == .minimized
                        // The self-minimizing overlay is drawn by the sibling
                        // bar above while minimized; a PiP-style overlay stays
                        // mounted here invisibly so its media keeps running.
                        if !(isMinimized && coordinator is SelfMinimizingOverlayCoordinator) {
                            coordinator.toPresentable()
                                .opacity(isMinimized ? 0 : 1)
                                .environment(\.isOverlayMinimized, isMinimized)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.elementDefault, value: navigationTabCoordinator.overlayPresentationMode)
                .animation(.elementDefault, value: navigationTabCoordinator.overlayModule)
            }
    }
    
    @ViewBuilder
    var tabView: some View {
        if horizontalSizeClass == .regular, #available(iOS 26, *) {
            tabRailLayout
        } else {
            tabViewLayout
        }
    }
    
    var tabRailLayout: some View {
        // The rail is always shown. Removing it hands its width back to the split view, which then has
        // room for its sidebar again, which shows the rail, ad infinitum. Keeping it means the split's
        // width never depends on it and the two can't drive each other.
        HStack(spacing: 0) {
            TabRailView(navigationTabCoordinator: navigationTabCoordinator, isFullScreen: isFullScreen)
                .background(railBackgroundColor.ignoresSafeArea())
                .animation(.easeInOut(duration: 0.4).disabledDuringTests(), value: railBackgroundColor)
                .overlay(alignment: .trailing) { NavigationSidebarDivider() }
                .zIndex(1)
            
            if let module = navigationTabCoordinator.tabModules.first(where: { $0.details.tag == navigationTabCoordinator.selectedTab }) {
                module.coordinator?.toPresentable()
                    .id(module.id)
            }
        }
        // Match the rail's background to the colour of the split view's detail (or the root if there isn't a split).
        .onPreferenceChange(CompoundBackgroundPreferenceKey.self) { background in
            guard #unavailable(iOS 27) else { return } // The background is only necessary for iOS 26's inset sidebar.
            railBackgroundColor = background?.colorValue ?? .compound.bgCanvasDefault
        }
        .introspect(.window, on: .supportedVersions) { window in
            guard self.window !== window else { return }
            
            DispatchQueue.main.async {
                self.window = window
                isFullScreen = window.isFullScreen
            }
        }
        .onGeometryChange(for: CGSize.self) { geometry in
            geometry.size // We don't need the size, but it's a signal to re-compute.
        } action: { _ in
            guard let newValue = window?.isFullScreen else { return }
            
            if newValue != isFullScreen {
                isFullScreen = newValue
            }
        }
    }
    
    var tabViewLayout: some View {
        TabView(selection: $navigationTabCoordinator.selectedTab) {
            ForEach(navigationTabCoordinator.tabModules) { module in
                Tab(value: module.details.tag) {
                    module.coordinator?.toPresentable()
                        .id(module.id)
                        .toolbar(module.details.barVisibility(in: horizontalSizeClass), for: .tabBar)
                } label: {
                    Label {
                        Text(module.details.title)
                    } icon: {
                        // AGENT-PLATFORM (Brief 0083, question 343)
                        module.details.iconView(isSelected: module.details.tag == navigationTabCoordinator.selectedTab,
                                                colorScheme: colorScheme,
                                                displayScale: displayScale)
                    }
                }
                .badge(module.details.badgeCount)
                .accessibilityValue(module.details.badgeAccessibilityValue ?? "", isEnabled: module.details.badgeAccessibilityValue != nil) // AGENT-PLATFORM (coverage walk F3)
                .accessibilityIdentifier(module.details.accessibilityIdentifier ?? "")
            }
        }
        .backportTabBarMinimizeBehaviorOnScrollDown()
        .introspect(.tabView, on: .supportedVersions, customize: configure)
    }
    
    private func configure(_ tabBarController: UITabBarController) {
        standardAppearance.configureWithDefaultBackground()
        // AGENT-PLATFORM (decision 306): the filled blue under the badge's white count (4.81:1; #0A84FF was 3.65:1 in dark).
        standardAppearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .compound.bgAccentRest // iPhone Portrait
        standardAppearance.compactInlineLayoutAppearance.normal.badgeBackgroundColor = .compound.bgAccentRest // iPhone Landscape
        standardAppearance.inlineLayoutAppearance.normal.badgeBackgroundColor = .compound.bgAccentRest // iPadOS 17 (doesn't work for 18+)
        // AGENT-PLATFORM (Brief 0083): the selected state's too, on every layout. On iPhone (iOS 27 and 18.6) the app's
        // selected badge already took the normal colour; only the audit's preview window kept the system red (DECISIONS).
        standardAppearance.stackedLayoutAppearance.selected.badgeBackgroundColor = .compound.bgAccentRest
        standardAppearance.compactInlineLayoutAppearance.selected.badgeBackgroundColor = .compound.bgAccentRest
        standardAppearance.inlineLayoutAppearance.selected.badgeBackgroundColor = .compound.bgAccentRest
        // AGENT-PLATFORM (Brief 0083, decision 310): before Liquid Glass the selected title is white in dark and its
        // icon stays blue, as the storyboard draws it; the blue title read 3.9:1 over rows under the translucent bar.
        if #unavailable(iOS 26) {
            let selectedTitle: [NSAttributedString.Key: Any] = [.foregroundColor: Self.preGlassSelectedTitleColor]
            standardAppearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedTitle
            standardAppearance.compactInlineLayoutAppearance.selected.titleTextAttributes = selectedTitle
            standardAppearance.inlineLayoutAppearance.selected.titleTextAttributes = selectedTitle
        }
        tabBarController.tabBar.standardAppearance = standardAppearance
        
        // AGENT-PLATFORM (Brief 0082 E2E): on iOS 27 a tab bar button copies its `UITab`'s identifier only
        // when the button is configured, which can be before SwiftUI has written the `Tab`'s identifier and
        // then never again: the E2E scenarios FD1, FD3, FD8 and FD10 found no Feed tab for 30 s. Each update
        // gives the identifier to the tab and to its buttons, found by title (unique per tab bar).
        let identifiers = navigationTabCoordinator.tabModules.reduce(into: [String: String]()) { identifiers, module in
            identifiers[module.details.title] = module.details.accessibilityIdentifier
        }
        for tab in tabBarController.tabs {
            if let identifier = identifiers[tab.title] {
                tab.accessibilityIdentifier = identifier
            }
        }
        Self.applyIdentifiers(identifiers, toButtonsIn: tabBarController.tabBar)
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 310): light keeps the tint's blue, dark takes the primary text colour.
    private static var preGlassSelectedTitleColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? .compound.textPrimary : .compound.textActionAccent
        }
    }
    
    /// The tab bar's buttons are UIKit's own views; each is labelled with its tab's title.
    private static func applyIdentifiers(_ identifiers: [String: String], toButtonsIn view: UIView) {
        if view is UIControl, let label = view.accessibilityLabel, let identifier = identifiers[label] {
            view.accessibilityIdentifier = identifier
        }
        for subview in view.subviews {
            applyIdentifiers(identifiers, toButtonsIn: subview)
        }
    }
}

struct TabRailView<Tag: Hashable>: View {
    @Environment(\.colorScheme) private var colorScheme // AGENT-PLATFORM (Brief 0083, question 343)
    @Environment(\.displayScale) private var displayScale // AGENT-PLATFORM (Brief 0083, question 343)
    
    let navigationTabCoordinator: NavigationTabCoordinator<Tag>
    let isFullScreen: Bool
    
    var topPadding: CGFloat {
        // Add additional top padding on iPad when the traffic light buttons are shown.
        isFullScreen || ProcessInfo.processInfo.isiOSAppOnMac ? 0 : 48
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(navigationTabCoordinator.tabModules) { module in
                    let isSelected = module.details.tag == navigationTabCoordinator.selectedTab
                    Button {
                        navigationTabCoordinator.selectedTab = module.details.tag
                    } label: {
                        Label {
                            Text(module.details.title)
                        } icon: {
                            // AGENT-PLATFORM (Brief 0083, question 343)
                            module.details.iconView(isSelected: isSelected, colorScheme: colorScheme, displayScale: displayScale)
                        }
                    }
                    .buttonStyle(TabButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier(module.details.accessibilityIdentifier ?? "")
                    .accessibilityValue(module.details.badgeAccessibilityValue ?? "", isEnabled: module.details.badgeAccessibilityValue != nil) // AGENT-PLATFORM (coverage walk F3)
                    .overlay(alignment: .topTrailing) {
                        if module.details.badgeCount > 0 {
                            NotificationCountBadge(count: module.details.badgeCount, size: .small)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, topPadding)
            .padding(.bottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
    }
    
    struct TabButtonStyle: ButtonStyle {
        let isSelected: Bool
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .labelStyle(.iconOnly)
                .foregroundStyle(.compound.iconPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(capsuleColor(isPressed: configuration.isPressed), in: .capsule)
                .contentShape(.capsule)
        }
        
        func capsuleColor(isPressed: Bool) -> Color {
            if isSelected {
                .compound.bgSubtleSecondary
            } else if isPressed {
                .compound.bgSubtleSecondary.opacity(0.5)
            } else {
                .clear
            }
        }
    }
}

private extension UIWindow {
    var isFullScreen: Bool {
        frame.size == windowScene?.screen.bounds.size
    }
}
