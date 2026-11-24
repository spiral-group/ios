//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3 A3): the assistant's welcome and its starters, in the live timeline only.
//

import Foundation

extension TimelineViewModel {
    func installSpiralWelcomeWatch() {
        guard state.timelineKind == .live else { return }
        spiralWelcomeWatch = SpiralWelcomeWatch(store: userSession.agentsStore) { [weak self] extras in
            guard let self, state.spiralWelcomeExtras != extras else { return }
            state.spiralWelcomeExtras = extras
        }
    }

    /// The starters show until the person writes anything here; a starter they tap is their first message.
    func updateSpiralWelcome(_ items: [RoomTimelineItemProtocol]) {
        guard let spiralWelcomeWatch else { return }
        let welcome = items.lazy.compactMap { $0 as? SpiralNoticeRoomTimelineItem }.first { $0.notice.isPersonalWelcome }
        let ownerHasWritten = welcome != nil && items.contains { ($0 as? EventBasedMessageTimelineItemProtocol)?.isOutgoing == true }
        spiralWelcomeWatch.update(welcomeSender: welcome?.sender.id, ownerHasWritten: ownerHasWritten)
    }

    func sendWelcomeStarter(_ starter: SpiralWelcomeStarter) async {
        guard state.spiralWelcomeExtras == .starters else { return }
        // Hidden at once, so a second tap can't send another before the timeline shows the first.
        spiralWelcomeWatch?.noteStarterSent()
        await timelineController.sendMessage(starter.message, html: nil, inReplyToEventID: nil, intentionalMentions: .empty)
        scrollToBottom()
    }
}
