//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Combine
@testable import Spiral
import Testing

@MainActor
struct SecureBackupRecoveryKeyScreenViewModelTests {
    /// The unknown state isn't a dead end: Retry reads the recovery state again (1.0.2 critic polish).
    @Test
    func retryReadsTheRecoveryStateAgain() {
        let recoveryState = CurrentValueSubject<SecureBackupRecoveryState, Never>(.unknown)
        let controller = SecureBackupControllerMock()
        controller.recoveryState = recoveryState.asCurrentValuePublisher()
        let viewModel = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                               userIndicatorController: UserIndicatorControllerMock(),
                                                               isModallyPresented: true)
        #expect(viewModel.context.viewState.mode == .unknown)
        #expect(viewModel.context.viewState.title == UntranslatedL10n.screenRecoveryKeyUnknownTitleSpiral)

        recoveryState.send(.disabled)
        viewModel.context.send(viewAction: .retry)

        #expect(viewModel.context.viewState.mode == .setupRecovery)
    }

    /// Still unknown, Retry leaves the screen as it was.
    @Test
    func retryWhileStillUnknownStaysUnknown() {
        let controller = SecureBackupControllerMock(.init(recoveryState: .unknown))
        let viewModel = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                               userIndicatorController: UserIndicatorControllerMock(),
                                                               isModallyPresented: true)

        viewModel.context.send(viewAction: .retry)

        #expect(viewModel.context.viewState.mode == .unknown)
    }
}
