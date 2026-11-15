//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import MatrixRustSDK
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct SessionVerificationRequestDetailsView: View {
    let details: SessionVerificationRequestDetails
    let isUserVerification: Bool
    let mediaProvider: MediaProviderProtocol?
    
    var body: some View {
        if isUserVerification {
            userRequestDetails
        } else {
            deviceRequestDetails
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decision 313): the person as a row of the identity path's card, the name over the ID.
    private var userRequestDetails: some View {
        SpiralCard {
            HStack(spacing: CompoundDesignTokens.space3X) {
                LoadableAvatarImage(url: details.senderProfile.avatarURL,
                                    name: details.senderProfile.displayName,
                                    contentID: details.senderProfile.id,
                                    avatarSize: .user(on: .sessionVerification),
                                    mediaProvider: mediaProvider)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(details.senderProfile.displayName ?? details.senderProfile.id)
                        .font(.compound.bodyLGSemibold)
                        .foregroundColor(.compound.textPrimary)
                    
                    if details.senderProfile.displayName != nil {
                        Text(details.senderProfile.id)
                            .font(.compound.bodyMD)
                            .foregroundColor(.compound.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.vertical, CompoundDesignTokens.space3X)
        }
    }
    
    // AGENT-PLATFORM (Brief 0083, decisions 313 and 314): the device as the rows of the identity path's card, the
    // warning under it in Spiral's copy.
    private var deviceRequestDetails: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space4X) {
            SpiralCard {
                SpiralCardRow(showsSeparator: true) {
                    let displayName = isUserVerification ? details.senderProfile.displayName : details.deviceDisplayName
                    Text(displayName ?? details.senderProfile.id)
                        .font(.compound.bodyLGSemibold)
                        .foregroundColor(.compound.textPrimary)
                }
                
                detailRow(title: L10n.screenSessionVerificationRequestDetailsTimestamp,
                          value: details.firstSeenDate.formattedMinimal(),
                          showsSeparator: true)
                
                detailRow(title: L10n.commonDeviceId, value: details.deviceID, showsSeparator: false)
            }
            
            Text(UntranslatedL10n.screenSessionVerificationRequestFooterSpiral)
                .font(.compound.bodyMDSemibold)
                .foregroundColor(.compound.textPrimary)
                .padding(.horizontal, CompoundDesignTokens.space4X)
        }
    }
    
    private func detailRow(title: String, value: String, showsSeparator: Bool) -> some View {
        SpiralCardRow(showsSeparator: showsSeparator) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
                Text(value)
                    .font(.compound.bodyLG)
                    .foregroundColor(.compound.textPrimary)
            }
        }
    }
}

struct SessionVerificationRequestDetailsView_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083)
    static let details = SessionVerificationRequestDetails(senderProfile: UserProfile(userID: "@bob:matrix.org",
                                                                                      displayName: "Billy bob",
                                                                                      avatarURL: .mockMXCUserAvatar),
                                                           flowID: "123",
                                                           deviceID: "CODEMISTAKE",
                                                           deviceDisplayName: "Bob's Element X iOS",
                                                           firstSeenDate: .init(timeIntervalSince1970: 0))
    
    static var previews: some View {
        SessionVerificationRequestDetailsView(details: details,
                                              isUserVerification: true,
                                              mediaProvider: MediaProviderMock(.init()))
            .padding()
            .previewDisplayName("User")
        
        SessionVerificationRequestDetailsView(details: details,
                                              isUserVerification: false,
                                              mediaProvider: MediaProviderMock(.init()))
            .padding()
            .previewDisplayName("Device")
    }
}
