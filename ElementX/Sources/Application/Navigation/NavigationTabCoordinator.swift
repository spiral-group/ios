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
        let icon: KeyPath<CompoundIcons, Image>
        let selectedIcon: KeyPath<CompoundIcons, Image>
        /// When `true` the tab is given the `.search` role, which on iOS 26 detaches it
        /// into the trailing search button in the tab bar.
        let isSearch: Bool
        var badgeCount = 0
        
        // AGENT-PLATFORM (coverage walk F3): the badge itself is not in the accessibility
        // tree; the tab's value carries the count for VoiceOver and UI tests.
        var badgeAccessibilityValue: String? {
            badgeCount > 0 ? UntranslatedL10n.a11yTabBadgeCount(badgeCount) : nil
        }
        
        /// Provide the tab's split coordinator in here to have the tab bar automatically hidden
        /// when pushing a child into the split view's details on iPhone/compact iPad.
        weak var navigationSplitCoordinator: NavigationSplitCoordinator?
        
        init(tag: Tag, title: String, icon: KeyPath<CompoundIcons, Image>, selectedIcon: KeyPath<CompoundIcons, Image>, isSearch: Bool = false) {
            self.tag = tag
            self.title = title
            self.icon = icon
            self.selectedIcon = selectedIcon
            self.isSearch = isSearch
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
    var selectedTab: Tag? {
        didSet {
            if oldValue != selectedTab {
                previousTab = oldValue
            }
        }
    }
    
    /// The tab that was selected before the current one, used to return to it (e.g. cancelling search).
    private(set) var previousTab: Tag?
    
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

private struct NavigationTabCoordinatorView<Tag: Hashable>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @Bindable var navigationTabCoordinator: NavigationTabCoordinator<Tag>
    
    @State private var standardAppearance = UITabBarAppearance()
    @State private var window: UIWindow?
    @State private var isFullScreen = true
    @State private var isRailVisible = true
    
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
    
    /// The column visibility of the split coordinator for the currently selected tab, if any.
    private var selectedTabSplitColumnVisibility: NavigationSplitViewVisibility {
        let selectedTabDetails = navigationTabCoordinator.tabModules
            .first { $0.details.tag == navigationTabCoordinator.selectedTab }?.details
        return selectedTabDetails?.navigationSplitCoordinator?.columnVisibility ?? .all
    }
    
    var tabRailLayout: some View {
        HStack(spacing: 0) {
            if isRailVisible {
                TabRailView(navigationTabCoordinator: navigationTabCoordinator, isFullScreen: isFullScreen)
            }
            
            if let module = navigationTabCoordinator.tabModules.first(where: { $0.details.tag == navigationTabCoordinator.selectedTab }) {
                module.coordinator?.toPresentable()
                    .id(module.id)
            }
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
        .onChange(of: selectedTabSplitColumnVisibility, initial: true) {
            // The rail consumes width, which feeds back into the split's column visibility (not the
            // same as flattening everything into the single stack), creating an observation tracking
            // feedback loop that locks up the app while resizing.
            //
            // Use a stored value (instead of a computed value) that is updated on the next run loop to break the loop.
            DispatchQueue.main.async { isRailVisible = selectedTabSplitColumnVisibility != .detailOnly }
        }
    }
    
    var tabViewLayout: some View {
        TabView(selection: $navigationTabCoordinator.selectedTab) {
            ForEach(navigationTabCoordinator.tabModules) { module in
                Tab(value: module.details.tag, role: module.details.isSearch ? .search : nil) {
                    module.coordinator?.toPresentable()
                        .id(module.id)
                        .toolbar(module.details.barVisibility(in: horizontalSizeClass), for: .tabBar)
                } label: {
                    Label {
                        Text(module.details.title)
                    } icon: {
                        CompoundIcon(module.details.tag == navigationTabCoordinator.selectedTab ? module.details.selectedIcon : module.details.icon)
                    }
                }
                .badge(module.details.badgeCount)
                .accessibilityValue(module.details.badgeAccessibilityValue ?? "", isEnabled: module.details.badgeAccessibilityValue != nil) // AGENT-PLATFORM (coverage walk F3)
            }
        }
        .backportTabBarMinimizeBehaviorOnScrollDown()
        .introspect(.tabView, on: .supportedVersions, customize: configureAppearance)
    }
    
    private func configureAppearance(_ tabBarController: UITabBarController) {
        standardAppearance.configureWithDefaultBackground()
        standardAppearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .compound.iconAccentPrimary // iPhone Portrait
        standardAppearance.compactInlineLayoutAppearance.normal.badgeBackgroundColor = .compound.iconAccentPrimary // iPhone Landscape
        standardAppearance.inlineLayoutAppearance.normal.badgeBackgroundColor = .compound.iconAccentPrimary // iPadOS 17 (doesn't work for 18+)
        tabBarController.tabBar.standardAppearance = standardAppearance
    }
}

struct TabRailView<Tag: Hashable>: View {
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
                            CompoundIcon(isSelected ? module.details.selectedIcon : module.details.icon)
                        }
                    }
                    .buttonStyle(TabButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityValue(module.details.badgeAccessibilityValue ?? "", isEnabled: module.details.badgeAccessibilityValue != nil) // AGENT-PLATFORM (coverage walk F3)
                    .badge(10) // TODO: Check if this works.
                }
            }
            .padding(.leading, 8)
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
