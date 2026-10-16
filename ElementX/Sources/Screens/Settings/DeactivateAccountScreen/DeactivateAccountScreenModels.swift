//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Foundation

enum DeactivateAccountScreenViewModelAction {
    case accountDeactivated
}

struct DeactivateAccountScreenViewState: BindableState {
    let info: AttributedString
    let infoPoint1: AttributedString
    let infoPoint2: AttributedString
    let infoPoint3: AttributedString
    let infoPoint4: AttributedString
    
    // AGENT-PLATFORM (Brief 0078): a Spiral account is deleted through the
    // platform — no password to confirm, messages always erased, the
    // assistant goes with it. The screen names no chat bridges: they are
    // off (decision 60).
    let isSpiralAccount: Bool
    let infoPointAssistant: AttributedString?
    
    var bindings = DeactivateAccountScreenViewStateBindings()
    
    init(isSpiralAccount: Bool = false) {
        self.isSpiralAccount = isSpiralAccount
        infoPoint4 = AttributedString(isSpiralAccount ? UntranslatedL10n.screenDeactivateAccountSpiralListItemMessages : L10n.screenDeactivateAccountListItem4)
        infoPointAssistant = isSpiralAccount ? AttributedString(UntranslatedL10n.screenDeactivateAccountSpiralListItemAssistant) : nil
        
        // AGENT-PLATFORM: Spiral's own copy, so the ru/uk sentences read as statements.
        if isSpiralAccount {
            info = Self.bolding(UntranslatedL10n.screenDeactivateAccountSpiralDescription, UntranslatedL10n.screenDeactivateAccountSpiralDescriptionBoldPart)
            infoPoint1 = Self.bolding(UntranslatedL10n.screenDeactivateAccountSpiralListItem1, UntranslatedL10n.screenDeactivateAccountSpiralListItem1BoldPart)
            infoPoint2 = AttributedString(UntranslatedL10n.screenDeactivateAccountSpiralListItem2)
            infoPoint3 = AttributedString(UntranslatedL10n.screenDeactivateAccountSpiralListItem3)
        } else {
            info = Self.bolding(L10n.screenDeactivateAccountDescription, L10n.screenDeactivateAccountDescriptionBoldPart)
            infoPoint1 = Self.bolding(L10n.screenDeactivateAccountListItem1, L10n.screenDeactivateAccountListItem1BoldPart)
            infoPoint2 = AttributedString(L10n.screenDeactivateAccountListItem2)
            infoPoint3 = AttributedString(L10n.screenDeactivateAccountListItem3)
        }
    }
    
    private static func bolding(_ template: (String) -> String, _ boldPart: String) -> AttributedString {
        let boldPlaceholder = "{bold}"
        var attributedString = AttributedString(template(boldPlaceholder))
        var boldString = AttributedString(boldPart)
        boldString.bold()
        attributedString.replace(boldPlaceholder, with: boldString)
        return attributedString
    }
}

struct DeactivateAccountScreenViewStateBindings {
    var password = ""
    var eraseData = false
    var alertInfo: AlertInfo<DeactivateAccountScreenAlert>?
}

enum DeactivateAccountScreenAlert {
    case confirmation
    case deactivationFailed
    case handleConfirmation // AGENT-PLATFORM (decision 112)
}

enum DeactivateAccountScreenViewAction {
    case deactivate
}
