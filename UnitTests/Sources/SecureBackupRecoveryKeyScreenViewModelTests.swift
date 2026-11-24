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

    /// DEBT (1.0.3): a person on «Couldn't check your recovery key» saw nothing happen on Retry. The screen now settles
    /// by itself once the state arrives.
    @Test
    func theUnknownStateSettlesOnceTheStateArrives() async throws {
        let recoveryState = CurrentValueSubject<SecureBackupRecoveryState, Never>(.unknown)
        let controller = SecureBackupControllerMock()
        controller.recoveryState = recoveryState.asCurrentValuePublisher()
        let viewModel = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                               userIndicatorController: UserIndicatorControllerMock(),
                                                               isModallyPresented: true)
        #expect(viewModel.context.viewState.mode == .unknown)
        
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.mode)) { $0 == .changeRecovery }
        recoveryState.send(.enabled)
        try await settled.fulfill()
    }
    
    /// Still unknown, Retry waits for the state with a loader Cancel isn't hidden by, and takes it when it comes.
    @Test
    func retryWhileStillUnknownWaitsForTheState() async throws {
        let recoveryState = CurrentValueSubject<SecureBackupRecoveryState, Never>(.unknown)
        let controller = SecureBackupControllerMock()
        controller.recoveryState = recoveryState.asCurrentValuePublisher()
        let indicators = UserIndicatorControllerMock()
        let viewModel = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                               userIndicatorController: indicators,
                                                               isModallyPresented: true)
        
        viewModel.context.send(viewAction: .retry)
        let loader = try #require(indicators.submitIndicatorDelayReceivedArguments?.indicator)
        #expect(loader.allowsInteraction)
        #expect(viewModel.context.viewState.mode == .unknown)
        
        let settled = deferFulfillment(viewModel.context.observe(\.viewState.mode)) { $0 == .fixRecovery }
        recoveryState.send(.incomplete)
        try await settled.fulfill()
        #expect(indicators.retractIndicatorWithIdReceivedId == loader.id)
        #expect(viewModel.context.alertInfo == nil)
    }
    
    /// A state that never comes ends the wait with a message, not a silent spinner.
    @Test
    func retryThatNeverLearnsTheStateSaysSo() async throws {
        let controller = SecureBackupControllerMock(.init(recoveryState: .unknown))
        let indicators = UserIndicatorControllerMock()
        let viewModel = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                               userIndicatorController: indicators,
                                                               isModallyPresented: true,
                                                               retryTimeout: .milliseconds(50))
        
        let alert = deferFulfillment(viewModel.context.observe(\.viewState.bindings.alertInfo)) { $0 != nil }
        viewModel.context.send(viewAction: .retry)
        try await alert.fulfill()
        
        #expect(viewModel.context.viewState.mode == .unknown)
        #expect(indicators.retractIndicatorWithIdCalled)
    }
    
    /// Fable M2: the screen leaving mid-wait takes its persistent loader with it.
    @Test
    func aScreenThatGoesAwayMidRetryRetractsItsLoader() async throws {
        let controller = SecureBackupControllerMock(.init(recoveryState: .unknown))
        let indicators = UserIndicatorControllerMock()
        var viewModel: SecureBackupRecoveryKeyScreenViewModel? = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                                                                         userIndicatorController: indicators,
                                                                                                         isModallyPresented: false)
        viewModel?.context.send(viewAction: .retry)
        let loader = try #require(indicators.submitIndicatorDelayReceivedArguments?.indicator)
        #expect(!indicators.retractIndicatorWithIdCalled)
        
        viewModel = nil
        
        #expect(viewModel == nil)
        #expect(indicators.retractIndicatorWithIdReceivedId == loader.id)
    }
    
    /// Fable follow-up: an old screen's late deinit retracts only its own loader, never a newer screen's.
    @Test
    func eachScreenRetractsOnlyItsOwnLoader() throws {
        let controller = SecureBackupControllerMock(.init(recoveryState: .unknown))
        let indicators = UserIndicatorControllerMock()
        var old: SecureBackupRecoveryKeyScreenViewModel? = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                                                                   userIndicatorController: indicators,
                                                                                                   isModallyPresented: false)
        old?.context.send(viewAction: .retry)
        let oldLoader = try #require(indicators.submitIndicatorDelayReceivedArguments?.indicator)
        let new = SecureBackupRecoveryKeyScreenViewModel(secureBackupController: controller,
                                                         userIndicatorController: indicators,
                                                         isModallyPresented: false)
        new.context.send(viewAction: .retry)
        let newLoader = try #require(indicators.submitIndicatorDelayReceivedArguments?.indicator)
        #expect(newLoader.id != oldLoader.id)
        
        old = nil
        
        #expect(old == nil)
        #expect(indicators.retractIndicatorWithIdReceivedInvocations == [oldLoader.id])
    }
}
