//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0078): Settings > About reaches the acknowledgements.
//

@testable import ElementX
import Testing

@MainActor
struct LegalInformationScreenViewModelTests {
    @Test
    func openSourceLicensesOpensTheAppsSettingsPage() {
        let appMediator = AppMediatorMock()
        let viewModel = LegalInformationScreenViewModel(appSettings: AppSettings.volatile(), appMediator: appMediator)

        viewModel.context.send(viewAction: .openAcknowledgements)

        #expect(appMediator.openAppSettingsCallsCount == 1)
    }
}
