//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

// AGENT-PLATFORM (Brief 0078): Developer options opened in a Release build after seven
// taps on the version — a hidden feature App Review flags (2.3.1). They are for Debug
// (and Nightly) builds only; a Debug build behaves as before.

@testable import ElementX
import Testing

@MainActor
struct SpiralDeveloperOptionsGateTests {
    @Test
    func sevenTapsDoNothingInRelease() {
        let appSettings = AppSettings.volatile()
        appSettings.developerOptionsEnabled = false
        let viewModel = makeViewModel(appSettings: appSettings, allowsDeveloperOptions: false)

        viewModel.context.send(viewAction: .enableDeveloperOptions)

        #expect(!appSettings.developerOptionsEnabled)
        #expect(!viewModel.context.viewState.showDeveloperOptions)
    }

    @Test
    func aStoredSwitchFromAnOlderBuildStaysHiddenInRelease() {
        let appSettings = AppSettings.volatile()
        appSettings.developerOptionsEnabled = true
        let viewModel = makeViewModel(appSettings: appSettings, allowsDeveloperOptions: false)

        #expect(!viewModel.context.viewState.showDeveloperOptions)

        // Nor does a later change to the stored switch reach the screen.
        appSettings.developerOptionsEnabled = false
        appSettings.developerOptionsEnabled = true
        #expect(!viewModel.context.viewState.showDeveloperOptions)
    }

    @Test
    func sevenTapsStillToggleThemInDebug() {
        let appSettings = AppSettings.volatile()
        appSettings.developerOptionsEnabled = false
        let viewModel = makeViewModel(appSettings: appSettings, allowsDeveloperOptions: true)
        #expect(!viewModel.context.viewState.showDeveloperOptions)

        viewModel.context.send(viewAction: .enableDeveloperOptions)

        #expect(appSettings.developerOptionsEnabled)
        #expect(viewModel.context.viewState.showDeveloperOptions)
    }

    @Test
    func theBuildTypeDecidesByDefault() {
        // The unit tests run a Debug build, which keeps upstream's default: shown.
        #expect(AppSettings.appBuildType == .debug)
        let viewModel = makeViewModel(appSettings: AppSettings.volatile())
        #expect(viewModel.context.viewState.showDeveloperOptions)
    }

    // MARK: - Helpers

    private func makeViewModel(appSettings: AppSettings, allowsDeveloperOptions: Bool? = nil) -> SettingsScreenViewModel {
        let userSession = UserSessionMock(.init(clientProxy: ClientProxyMock(.init(userID: "@alice:spiral.md"))))
        if let allowsDeveloperOptions {
            return SettingsScreenViewModel(userSession: userSession,
                                           appSettings: appSettings,
                                           isBugReportServiceEnabled: false,
                                           isInSecondaryWindow: false,
                                           userIndicatorController: UserIndicatorControllerMock(),
                                           allowsDeveloperOptions: allowsDeveloperOptions)
        }
        return SettingsScreenViewModel(userSession: userSession,
                                       appSettings: appSettings,
                                       isBugReportServiceEnabled: false,
                                       isInSecondaryWindow: false,
                                       userIndicatorController: UserIndicatorControllerMock())
    }
}
