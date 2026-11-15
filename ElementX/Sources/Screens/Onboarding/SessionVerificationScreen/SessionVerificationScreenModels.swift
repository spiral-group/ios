//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

enum SessionVerificationScreenViewModelAction {
    case finished
}

enum SessionVerificationScreenViewAction {
    case acceptVerificationRequest
    case ignoreVerificationRequest
    case requestVerification
    case restart
    case accept
    case decline
    case cancel
    case done
}

struct SessionVerificationScreenViewState: BindableState {
    let flow: SessionVerificationScreenFlow
    let learnMoreURL: URL
    
    var verificationState: SessionVerificationScreenStateMachine.State
    
    var headerIcon: (keyPath: KeyPath<CompoundIcons, Image>, style: BigIcon.Style) {
        switch verificationState {
        case .initial, .acceptingVerificationRequest, .requestingVerification,
             .verificationRequestAccepted, .startingSasVerification, .sasVerificationStarted,
             .cancelling:
            switch flow {
            case .deviceInitiator, .deviceResponder:
                return (\.devices, .defaultSolid)
            case .userInitiator, .userResponder:
                return (\.userProfileSolid, .defaultSolid)
            }
        // AGENT-PLATFORM (Brief 0083, decision 323): the solid face; the outline one draws filled in dark.
        case .showingChallenge:
            return (\.reactionSolid, .defaultSolid)
        case .acceptingChallenge:
            return (\.reactionSolid, .defaultSolid)
        case .decliningChallenge:
            return (\.reactionSolid, .defaultSolid)
        case .verified:
            return (\.checkCircleSolid, .successSolid)
        case .cancelled:
            return (\.infoSolid, .alertSolid)
        }
    }
    
    var titleAccessibilityIdentifier: String {
        verificationState == .verified ? A11yIdentifiers.sessionVerificationScreen.verificationComplete : ""
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 314): Spiral's copy, through `Untranslated.strings`' `*_spiral` keys.
    var title: String? {
        switch verificationState {
        case .initial, .acceptingVerificationRequest, .requestingVerification,
             .verificationRequestAccepted, .startingSasVerification, .sasVerificationStarted,
             .cancelling:
            switch flow {
            case .deviceInitiator:
                return UntranslatedL10n.screenSessionVerificationUseAnotherDeviceTitleSpiral
            case .userInitiator:
                return UntranslatedL10n.screenSessionVerificationUserInitiatorTitleSpiral
            case .deviceResponder, .userResponder:
                return UntranslatedL10n.screenSessionVerificationRequestTitleSpiral
            }
        case .showingChallenge:
            return UntranslatedL10n.screenSessionVerificationCompareEmojisTitleSpiral
        case .acceptingChallenge:
            return UntranslatedL10n.screenSessionVerificationCompareEmojisTitleSpiral
        case .decliningChallenge:
            return UntranslatedL10n.screenSessionVerificationCompareEmojisTitleSpiral
        case .verified:
            switch flow {
            case .deviceInitiator, .deviceResponder:
                return UntranslatedL10n.screenSessionVerificationDeviceVerifiedSpiral
            case .userInitiator, .userResponder:
                return UntranslatedL10n.commonVerificationCompleteSpiral
            }
        case .cancelled:
            return UntranslatedL10n.commonVerificationFailedSpiral
        }
    }
    
    var message: String {
        switch verificationState {
        case .initial, .acceptingVerificationRequest, .requestingVerification,
             .verificationRequestAccepted, .startingSasVerification, .sasVerificationStarted,
             .cancelling:
            switch flow {
            case .deviceInitiator:
                return UntranslatedL10n.screenSessionVerificationUseAnotherDeviceSubtitleSpiral
            case .userInitiator:
                return UntranslatedL10n.screenSessionVerificationUserInitiatorSubtitleSpiral
            case .deviceResponder:
                return UntranslatedL10n.screenSessionVerificationRequestSubtitleSpiral
            case .userResponder:
                return UntranslatedL10n.screenSessionVerificationUserResponderSubtitleSpiral
            }
        case .acceptingChallenge:
            return UntranslatedL10n.screenSessionVerificationCompareEmojisSubtitleSpiral
        case .decliningChallenge:
            return UntranslatedL10n.screenSessionVerificationCompareEmojisSubtitleSpiral
        case .showingChallenge:
            switch flow {
            case .deviceInitiator, .deviceResponder:
                return UntranslatedL10n.screenSessionVerificationCompareEmojisSubtitleSpiral
            case .userInitiator, .userResponder:
                return UntranslatedL10n.screenSessionVerificationCompareEmojisUserSubtitleSpiral
            }
        case .verified:
            switch flow {
            case .deviceInitiator, .deviceResponder:
                return UntranslatedL10n.screenSessionVerificationCompleteSubtitleSpiral
            case .userInitiator, .userResponder:
                return UntranslatedL10n.screenSessionVerificationCompleteUserSubtitleSpiral
            }
            
        case .cancelled:
            return UntranslatedL10n.screenSessionVerificationFailedSubtitleSpiral
        }
    }
    
    var isWaiting: Bool {
        switch verificationState {
        case .acceptingVerificationRequest, .requestingVerification, .verificationRequestAccepted,
             .startingSasVerification, .sasVerificationStarted, .cancelling:
            true
        default:
            false
        }
    }
    
    var showIgnoreButton: Bool {
        switch flow {
        case .deviceResponder, .userResponder:
            true
        default:
            false
        }
    }
}
