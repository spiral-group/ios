//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import SwiftUI
import Testing

/// Bug S6: Chats' lazy list measures a row, then places it at that height snapped to the screen's pixels.
/// An invite row that re-decides its buttons' layout at a hair less height is drawn a stacked button taller
/// than its slot: a gap above the name, its buttons under the next row.
@MainActor
struct HomeScreenInviteCellTests {
    private static let width = 393.0

    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility3], [0, 1])
    func theRowKeepsItsHeightWhenTheListPlacesIt(dynamicTypeSize: DynamicTypeSize, invite: Int) {
        let room = HomeScreenRoom(summary: [RoomSummary].mockInvites[invite])

        let measured = height(of: room, dynamicTypeSize: dynamicTypeSize, proposedHeight: .greatestFiniteMagnitude)
        let placed = height(of: room, dynamicTypeSize: dynamicTypeSize, proposedHeight: measured - 0.5)

        #expect(abs(placed - measured) < 1, "measured \(measured), placed \(placed)")
    }

    private func height(of room: HomeScreenRoom, dynamicTypeSize: DynamicTypeSize, proposedHeight: CGFloat) -> CGFloat {
        let cell = HomeScreenInviteCell(room: room,
                                        context: HomeScreenInviteCell_Previews.makeViewModel().context,
                                        hideInviteAvatars: false)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        return UIHostingController(rootView: cell).sizeThatFits(in: CGSize(width: Self.width, height: proposedHeight)).height
    }
}
