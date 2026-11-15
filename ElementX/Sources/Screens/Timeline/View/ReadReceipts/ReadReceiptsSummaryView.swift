//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SpiralComponents // AGENT-PLATFORM (Brief 0083)
import SwiftUI

struct ReadReceiptsSummaryView: View {
    let orderedReadReceipts: [ReadReceipt]
    @EnvironmentObject private var context: TimelineViewModel.Context
    
    // AGENT-PLATFORM (Brief 0083): iOS's grouped sheet, as the message's menu: the title centred as a sheet's
    // title, the readers as rows of one card.
    var body: some View {
        VStack(spacing: CompoundDesignTokens.space4X) {
            Text(L10n.commonSeenBy)
                .font(.compound.bodyLGSemibold)
                .foregroundColor(.compound.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, CompoundDesignTokens.space4X)
            ScrollView {
                SpiralCard(on: .groupedSheet) {
                    LazyVStack(spacing: 0) {
                        ForEach(orderedReadReceipts) { receipt in
                            ReadReceiptCell(readReceipt: receipt,
                                            memberState: context.viewState.members[receipt.userID],
                                            mediaProvider: context.mediaProvider)
                                .overlay(alignment: .bottom) {
                                    if receipt.id != orderedReadReceipts.last?.id {
                                        SpiralCardSeparator(leadingInset: ReadReceiptCell.textInset)
                                    }
                                }
                        }
                    }
                }
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .padding(.bottom, CompoundDesignTokens.space4X)
            }
        }
        .padding(.top, CompoundDesignTokens.space6X)
        .background(Color.compound.bgSubtleSecondaryLevel0.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(Color.compound.bgSubtleSecondaryLevel0)
        .presentationDragIndicator(.visible)
    }
}

struct ReadReceiptsSummaryView_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083): Spiral's gates
    static let viewModel = {
        let members: [RoomMemberProxyMock] = [
            .mockAlice,
            .mockBob,
            .mockCharlie,
            .mockDan
        ]
        let roomProxyMock = JoinedRoomProxyMock(.init(name: "Room", members: members))
        
        return TimelineViewModel(roomProxy: roomProxyMock,
                                 timelineController: TimelineControllerMock(.init()),
                                 userSession: UserSessionMock(.init()),
                                 mediaPlayerProvider: MediaPlayerProviderMock(),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appMediator: AppMediatorMock(.init()),
                                 analyticsService: AnalyticsServiceMock(.init()),
                                 emojiProvider: EmojiProvider(userSettings: .mock()),
                                 linkMetadataProvider: LinkMetadataProvider(),
                                 timelineControllerFactory: TimelineControllerFactoryMock(.init()))
    }()
    
    static let orderedReadReceipts: [ReadReceipt] = [
        .init(userID: "@alice:matrix.org", formattedTimestamp: "10:00"),
        .init(userID: "@bob:matrix.org", formattedTimestamp: "9:30"),
        .init(userID: "@charlie:matrix.org", formattedTimestamp: "9:00"),
        .init(userID: "@dan:matrix.org", formattedTimestamp: "8:30"),
        .init(userID: "@loading:matrix.org", formattedTimestamp: "Long time ago")
    ]
    
    static var previews: some View {
        ReadReceiptsSummaryView(orderedReadReceipts: orderedReadReceipts)
            .environmentObject(viewModel.context)
    }
}
