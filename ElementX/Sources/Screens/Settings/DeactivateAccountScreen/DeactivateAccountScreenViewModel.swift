//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import SwiftUI

typealias DeactivateAccountScreenViewModelType = StateStoreViewModelV2<DeactivateAccountScreenViewState, DeactivateAccountScreenViewAction>

// AGENT-PLATFORM (Brief 0078): what deleting a Spiral account needs.
struct SpiralAccountDeletion {
    let agentPlatformService: AgentPlatformServiceProtocol
    var authenticator: DeviceOwnerAuthenticatorProtocol = DeviceOwnerAuthenticator()
}

class DeactivateAccountScreenViewModel: DeactivateAccountScreenViewModelType, DeactivateAccountScreenViewModelProtocol {
    private let clientProxy: ClientProxyProtocol
    private let userIndicatorController: UserIndicatorControllerProtocol
    private let spiralDeletion: SpiralAccountDeletion? // AGENT-PLATFORM (Brief 0078)
    
    private let actionsSubject: PassthroughSubject<DeactivateAccountScreenViewModelAction, Never> = .init()
    var actionsPublisher: AnyPublisher<DeactivateAccountScreenViewModelAction, Never> {
        actionsSubject.eraseToAnyPublisher()
    }
    
    init(clientProxy: ClientProxyProtocol,
         userIndicatorController: UserIndicatorControllerProtocol,
         spiralDeletion: SpiralAccountDeletion? = nil) { // AGENT-PLATFORM (Brief 0078)
        self.clientProxy = clientProxy
        self.userIndicatorController = userIndicatorController
        self.spiralDeletion = spiralDeletion
        
        super.init(initialViewState: DeactivateAccountScreenViewState(isSpiralAccount: spiralDeletion != nil))
    }
    
    override func process(viewAction: DeactivateAccountScreenViewAction) {
        MXLog.info("View model: received view action: \(viewAction)")
        
        switch viewAction {
        case .deactivate:
            showDeactivationConfirmation()
        }
    }
    
    // MARK: - Private
    
    private let deactivatingIndicatorID = "\(DeactivateAccountScreenViewModel.self)-Deactivating"
    
    func showDeactivationConfirmation() {
        state.bindings.alertInfo = .init(id: .confirmation,
                                         title: L10n.screenDeactivateAccountTitle,
                                         message: L10n.screenDeactivateAccountConfirmationDialogContent,
                                         primaryButton: .init(title: L10n.actionDelete) {
                                             Task {
                                                 // AGENT-PLATFORM (Brief 0078): the platform deletes a Spiral account.
                                                 if let spiralDeletion = self.spiralDeletion {
                                                     await self.deleteSpiralAccount(spiralDeletion)
                                                 } else {
                                                     await self.deactivateAccount()
                                                 }
                                             }
                                         },
                                         secondaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil))
    }
    
    // AGENT-PLATFORM (Brief 0078): Face ID / the passcode, then `DELETE /me`.
    // Decision 112: a phone with no passcode has no owner check, so the
    // account's handle, typed out, confirms instead. A cancel or a lockout
    // still deletes nothing.
    func deleteSpiralAccount(_ deletion: SpiralAccountDeletion) async {
        switch await deletion.authenticator.authenticate(reason: UntranslatedL10n.screenDeactivateAccountSpiralAuthReason) {
        case .cancelled:
            return
        case .passcodeRequired:
            confirmWithHandle(deletion)
        case .authenticated:
            await deleteSpiralAccountConfirmed(deletion)
        }
    }
    
    private func confirmWithHandle(_ deletion: SpiralAccountDeletion) {
        let userID = clientProxy.userID
        var typed = ""
        let binding = Binding<String>(get: { typed }, set: { typed = $0 })
        state.bindings.alertInfo = .init(id: .handleConfirmation,
                                         title: L10n.screenDeactivateAccountTitle,
                                         message: UntranslatedL10n.screenDeactivateAccountSpiralHandlePrompt(Self.handle(of: userID)),
                                         primaryButton: .init(title: L10n.actionCancel, role: .cancel, action: nil),
                                         secondaryButton: .init(title: L10n.actionDelete, role: .destructive) { [weak self] in
                                             guard let self else { return }
                                             guard Self.isHandle(typed, of: userID) else {
                                                 state.bindings.alertInfo = .init(id: .deactivationFailed,
                                                                                  title: L10n.screenDeactivateAccountTitle,
                                                                                  message: UntranslatedL10n.screenDeactivateAccountSpiralHandleMismatch)
                                                 return
                                             }
                                             Task { await self.deleteSpiralAccountConfirmed(deletion) }
                                         },
                                         textFields: [.init(placeholder: UntranslatedL10n.screenDeactivateAccountSpiralHandlePlaceholder,
                                                            text: binding,
                                                            autoCapitalization: .never,
                                                            autoCorrectionDisabled: true)])
    }
    
    /// The handle as the person knows it: `@alice` for `@alice:spiral.md`.
    static func handle(of userID: String) -> String {
        "@" + localpart(of: userID)
    }
    
    /// The typed handle, with or without the `@`, in any case; with a server,
    /// it must be the account's own.
    static func isHandle(_ typed: String, of userID: String) -> Bool {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !typed.isEmpty, !typed.hasSuffix(":") else { return false }
        if typed.contains(":") {
            return (typed.hasPrefix("@") ? typed : "@" + typed) == userID.lowercased()
        }
        return localpart(of: typed) == localpart(of: userID).lowercased()
    }
    
    private static func localpart(of userID: String) -> String {
        let withoutSigil = userID.hasPrefix("@") ? String(userID.dropFirst()) : userID
        return withoutSigil.split(separator: ":", maxSplits: 1).first.map(String.init) ?? withoutSigil
    }
    
    /// A 404 means the account is already gone, which is the outcome asked for.
    private func deleteSpiralAccountConfirmed(_ deletion: SpiralAccountDeletion) async {
        userIndicatorController.submitIndicator(UserIndicator(id: deactivatingIndicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonPleaseWait,
                                                              persistent: true))
        MXLog.warning("Deleting the Spiral account.")
        
        switch await deletion.agentPlatformService.deleteAccount() {
        case .success, .failure(.notFound):
            MXLog.info("Spiral account deleted.")
            actionsSubject.send(.accountDeactivated)
        case .failure(let error):
            MXLog.error("Spiral account deletion failed: \(error)")
            userIndicatorController.retractIndicatorWithId(deactivatingIndicatorID)
            state.bindings.alertInfo = .init(id: .deactivationFailed,
                                             title: L10n.errorUnknown,
                                             message: UntranslatedL10n.screenDeactivateAccountSpiralFailed)
        }
    }
    
    func deactivateAccount() async {
        userIndicatorController.submitIndicator(UserIndicator(id: deactivatingIndicatorID,
                                                              type: .modal(progress: .indeterminate, interactiveDismissDisabled: true, allowsInteraction: false),
                                                              title: L10n.commonPleaseWait,
                                                              persistent: true))
        
        MXLog.warning("Deactivating account.")
        
        switch await clientProxy.deactivateAccount(password: state.bindings.password, eraseData: state.bindings.eraseData) {
        case .success:
            MXLog.info("Account deactivated.")
            actionsSubject.send(.accountDeactivated)
            return
        case .failure(let failure):
            MXLog.info("Deactivation failed \(failure).")
            state.bindings.alertInfo = .init(id: .deactivationFailed,
                                             title: L10n.errorUnknown,
                                             message: String(describing: failure))
            userIndicatorController.retractIndicatorWithId(deactivatingIndicatorID)
        }
    }
}
