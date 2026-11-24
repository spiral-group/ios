//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import SwiftUI

@Observable class NavigationRootCoordinator: CoordinatorProtocol, CustomStringConvertible {
    fileprivate var rootModule: NavigationModule? {
        didSet {
            if let oldValue {
                oldValue.tearDown()
            }
            
            if let rootModule {
                logPresentationChange("Set root", rootModule)
                rootModule.coordinator?.start()
            }
        }
    }
    
    /// The currently displayed coordinator
    var rootCoordinator: (any CoordinatorProtocol)? {
        rootModule?.coordinator
    }
    
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
    
    // periphery:ignore - might be useful to have
    // The currently presented sheet coordinator
    // Sheets will be presented through the NavigationSplitCoordinator if provided
    var sheetCoordinator: (any CoordinatorProtocol)? {
        sheetModule?.coordinator
    }
    
    /// The lowest-level `AlertInfo`, directly available to the root of the app.
    var alertInfo: AlertInfo<UUID>?
    
    // AGENT-PLATFORM (1.0.3, operator 2026-11-23): drawn over the root and under everything the root presents, so
    // one screen stays up while the root changes beneath it (the sign-in's logo until onboarding covers the tabs).
    fileprivate var coverModule: NavigationModule? {
        didSet {
            if let oldValue {
                logPresentationChange("Remove cover", oldValue)
                oldValue.tearDown()
            }
            
            if let coverModule {
                logPresentationChange("Set cover", coverModule)
                coverModule.coordinator?.start()
            }
        }
    }
    
    /// AGENT-PLATFORM (1.0.3): the coordinator drawn over the root, see `coverModule`.
    var coverCoordinator: (any CoordinatorProtocol)? {
        coverModule?.coordinator
    }
    
    /// Sets or replaces the presented coordinator
    /// - Parameter coordinator: the coordinator to display
    func setRootCoordinator(_ coordinator: (any CoordinatorProtocol)?, animated: Bool = true, dismissalCallback: (() -> Void)? = nil) {
        var transaction = Transaction()
        // AGENT-PLATFORM (1.0.3): under the cover nothing shows the change, and a crossfade still running when the
        // cover goes would show the old root again.
        transaction.disablesAnimations = !animated || coverModule != nil
        
        withTransaction(transaction) {
            guard let coordinator else {
                rootModule = nil
                return
            }
            
            rootModule = NavigationModule(coordinator, dismissalCallback: dismissalCallback)
        }
    }
    
    /// AGENT-PLATFORM (1.0.3): sets or removes the coordinator drawn over the root, see `coverModule`.
    func setCoverCoordinator(_ coordinator: (any CoordinatorProtocol)?, animated: Bool = false) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        
        withTransaction(transaction) {
            coverModule = coordinator.map { NavigationModule($0) }
        }
    }
    
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
    
    // MARK: - CoordinatorProtocol
    
    func toPresentable() -> AnyView {
        AnyView(NavigationRootCoordinatorView(rootCoordinator: self))
    }
    
    // MARK: - CustomStringConvertible
    
    var description: String {
        if let rootCoordinator = rootModule?.coordinator {
            return "NavigationRootCoordinator(\(rootCoordinator)"
        } else {
            return "NavigationRootCoordinator(Empty)"
        }
    }
    
    // MARK: - Private
    
    private func logPresentationChange(_ change: String, _ module: NavigationModule) {
        if let coordinator = module.coordinator {
            MXLog.info("\(self) \(change): \(coordinator)")
        }
    }
}

private struct NavigationRootCoordinatorView: View {
    @Bindable var rootCoordinator: NavigationRootCoordinator
    
    var body: some View {
        ZStack {
            rootCoordinator.rootModule?.coordinator?.toPresentable()
                .accessibilityHidden(rootCoordinator.coverModule != nil) // AGENT-PLATFORM (1.0.3)
            
            // AGENT-PLATFORM (1.0.3): see `coverModule`.
            if let coverModule = rootCoordinator.coverModule {
                coverModule.coordinator?.toPresentable()
                    .id(coverModule.id)
                    .transition(.opacity)
            }
        }
        .alert(item: $rootCoordinator.alertInfo)
        .animation(.elementDefault, value: rootCoordinator.rootModule)
        .animation(.elementDefault, value: rootCoordinator.coverModule) // AGENT-PLATFORM (1.0.3)
        .sheet(item: $rootCoordinator.sheetModule) { module in
            module.coordinator?.toPresentable()
        }
    }
}
