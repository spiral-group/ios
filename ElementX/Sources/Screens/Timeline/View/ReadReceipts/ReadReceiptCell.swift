//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralTokens // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct ReadReceiptCell: View {
    let readReceipt: ReadReceipt
    let memberState: RoomMemberState?
    let mediaProvider: MediaProviderProtocol?
    
    private var title: String {
        memberState?.displayName ?? readReceipt.userID
    }
    
    private var subtitle: String {
        guard title != readReceipt.userID else {
            return ""
        }
        return readReceipt.userID
    }
    
    /// Where the text starts: the separator under a row is inset to it.
    static let textInset = CompoundDesignTokens.space4X + SpiralAvatarSize.small + CompoundDesignTokens.space3X // AGENT-PLATFORM (Brief 0083)
    
    var body: some View {
        HStack(spacing: 12) {
            LoadableAvatarImage(url: memberState?.avatarURL,
                                name: memberState?.displayName,
                                contentID: readReceipt.userID,
                                avatarSize: .user(on: .readReceiptSheet),
                                mediaProvider: mediaProvider)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                // AGENT-PLATFORM (Brief 0083): a list row's type, the name in body text, as the reactions' senders.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.compound.bodyLG)
                        .foregroundColor(.compound.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let formattedTimestamp = readReceipt.formattedTimestamp {
                        Text(formattedTimestamp)
                            .font(.compound.bodySM)
                            .foregroundColor(.compound.textSecondary)
                            .lineLimit(1)
                    }
                }
                Text(subtitle)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 12) // AGENT-PLATFORM (Brief 0083): a list row's height
        .padding(.horizontal, 16)
    }
}

struct ReadReceiptCell_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        ReadReceiptCell(readReceipt: .init(userID: "@test:matrix.org",
                                           formattedTimestamp: "10:00"),
                        memberState: .init(displayName: "Test",
                                           avatarURL: nil,
                                           status: .init()),
                        mediaProvider: MediaProviderMock(.init()))
            .previewDisplayName("No Image")
        ReadReceiptCell(readReceipt: .init(userID: "@test:matrix.org",
                                           formattedTimestamp: "10:00"),
                        memberState: .init(displayName: "Test",
                                           avatarURL: .mockMXCUserAvatar,
                                           status: .init()),
                        mediaProvider: MediaProviderMock(.init()))
            .previewDisplayName("With Image")
        ReadReceiptCell(readReceipt: .init(userID: "@test:matrix.org",
                                           formattedTimestamp: "10:00"),
                        memberState: nil,
                        mediaProvider: MediaProviderMock(.init()))
            .previewDisplayName("Loading Member")
    }
}
