//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Intents
import SwiftUI

/// A basic window scene delegate used to configure the `WindowManager`.
///
/// We don't support multiple scenes right now, so the implementation is pretty basic.
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    weak static var windowManager: SecureWindowManagerProtocol!
    // AGENT-PLATFORM (Brief 0063): native CallKit Recents redial — see
    // `handleUserActivityIfNeeded` below; `import Intents` is for it.
    static var userActivityHandler: ((NSUserActivity) -> Void)?
    
    /// The app's main window scene identifier.
    static let mainSceneID = "Main"
    /// The user info key used by SwiftUI for a `WindowGroup`s `id` parameter.
    static let sceneIDKey = "com.apple.SwiftUI.sceneID"
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Self.windowManager.configure(withScene: windowScene, session: session)

        // AGENT-PLATFORM (Brief 0063)
        connectionOptions.userActivities.forEach { Self.handleUserActivityIfNeeded($0) }
    }

    // AGENT-PLATFORM (Brief 0063)
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        Self.handleUserActivityIfNeeded(userActivity)
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        Self.windowManager.handleSceneDisconnection(windowScene)
    }

    // AGENT-PLATFORM (Brief 0063)
    /// Recents redial delivers `INStartCallIntent` on modern iOS but the deprecated
    /// `INStartAudioCallIntent`/`INStartVideoCallIntent` activity types still show up,
    /// so match on the activity type prefix rather than one concrete intent class.
    static func handleUserActivityIfNeeded(_ userActivity: NSUserActivity) {
        MXLog.info("Received user activity: \(userActivity.activityType)")
        
        guard userActivity.activityType.hasPrefix("INStart") || userActivity.interaction?.intent is INStartCallIntent else {
            return
        }
        
        userActivityHandler?(userActivity)
    }
}
