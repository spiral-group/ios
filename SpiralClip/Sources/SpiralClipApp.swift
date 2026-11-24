//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip for invite links (Brief 0086).
//
// It carries the invitation across the App Store install: no SDK, no
// registration (ADR-0008), one request to `GET <host>/join/<token>`
// (spiral.md, or staging.spiral.md in a Staging build).
//

import SwiftUI

@main
struct SpiralClipApp: App {
    @State private var viewModel = ClipViewModel(handOff: ClipInviteHandOff(bundle: .main),
                                                 resolver: ClipInviteResolver(),
                                                 avatarLoader: ClipAvatarLoader())

    var body: some Scene {
        WindowGroup {
            ClipScreen(viewModel: viewModel)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { await viewModel.open(url) }
                }
                .task {
                    #if DEBUG
                    // A launch from Xcode or `simctl` with the scheme's URL, which only Xcode turns into an invocation.
                    if let url = ProcessInfo.processInfo.environment["_XCAppClipURL"].flatMap(URL.init(string:)) {
                        await viewModel.open(url)
                    }
                    #endif
                    // An invocation brings its URL right after launch; a launch without one shows the neutral welcome.
                    try? await Task.sleep(for: .seconds(2))
                    viewModel.invocationTimedOut()
                }
        }
    }
}
