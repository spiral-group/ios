//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

@testable import Spiral
import Testing

struct TimelineDeliveryStatusTests {
    private let person = RoomMemberProxyMock.mockAlice
    private let agent = RoomMemberProxyMock(with: .init(userID: "@assistant-alice:matrix.org", membership: .join))
    
    @Test
    func aMessageNobodyReadHasOneTick() {
        let message = ownMessage()
        let viewModel = makeViewModel(timelineItems: [message])
        
        #expect(deliveryStatus(of: message, in: viewModel) == .sent)
    }
    
    @Test
    func aReceiptOnALaterMessageGivesTwoTicks() {
        let earlier = ownMessage()
        let later = ownMessage(receipts: [person.userID])
        let viewModel = makeViewModel(timelineItems: [earlier, later])
        
        #expect(deliveryStatus(of: earlier, in: viewModel) == .read)
        #expect(deliveryStatus(of: later, in: viewModel) == .read)
    }
    
    @Test
    func anAgentInADMWithAPersonLeavesOneTick() {
        let message = ownMessage(receipts: [agent.userID])
        let viewModel = makeViewModel(timelineItems: [message], heroes: [person], isDirect: true)
        
        #expect(deliveryStatus(of: message, in: viewModel) == .sent)
        #expect(viewModel.context.viewState.hasReaders(message))
    }
    
    @Test
    func theAgentOfADMWithTheAgentGivesTwoTicks() {
        let message = ownMessage(receipts: [agent.userID])
        let viewModel = makeViewModel(timelineItems: [message], heroes: [agent], isDirect: true)
        
        #expect(deliveryStatus(of: message, in: viewModel) == .read)
    }
    
    @Test
    func sendingAndFailedKeepTheirOwnStates() {
        let message = ownMessage(receipts: [person.userID])
        let viewModel = makeViewModel(timelineItems: [message])
        
        #expect(deliveryStatus(of: message, in: viewModel, adjustedDeliveryStatus: .sending) == .sending)
        #expect(deliveryStatus(of: message, in: viewModel, adjustedDeliveryStatus: .sendingFailed(.unknown(reason: nil))) == nil)
    }
    
    @Test
    func otherPeoplesMessagesHaveNoTicks() {
        let message = ownMessage(isOutgoing: false, receipts: [person.userID])
        let viewModel = makeViewModel(timelineItems: [message])
        
        #expect(deliveryStatus(of: message, in: viewModel) == nil)
    }
    
    @Test
    func turningReceiptsOffLeavesOneTickAndNoSeenBy() {
        let message = ownMessage(receipts: [person.userID])
        let viewModel = makeViewModel(timelineItems: [message], sharePresence: false)
        
        #expect(deliveryStatus(of: message, in: viewModel) == .sent)
        #expect(!viewModel.context.viewState.hasReaders(message))
    }
    
    @Test
    func theStatusFollowsAnUpdate() async throws {
        let message = ownMessage()
        let timelineController = TimelineControllerMock(.init(timelineItems: [message]))
        let viewModel = makeViewModel(timelineController: timelineController)
        #expect(deliveryStatus(of: message, in: viewModel) == .sent)
        
        let deferred = deferFulfillment(viewModel.context.$viewState) { !$0.timelineState.readOwnItemIDs.isEmpty }
        timelineController.readProgress = .init(timelineItems: [ownMessage(id: message.id, receipts: [person.userID])],
                                                ownUserID: RoomMemberProxyMock.mockMe.userID)
        timelineController.callbacks.send(.updatedTimelineItems(timelineItems: [message], isSwitchingTimelines: false))
        try await deferred.fulfill()
        
        #expect(deliveryStatus(of: message, in: viewModel) == .read)
    }
    
    @Test
    func aMessageKeepsItsWidthWhenItIsRead() {
        let unread = ownMessage()
        let read = ownMessage(receipts: [person.userID])
        let incoming = ownMessage(isOutgoing: false)
        
        #expect(unread.trailingReservedSize == read.trailingReservedSize)
        #expect(unread.trailingReservedSize.width > incoming.trailingReservedSize.width)
    }
    
    @Test
    func theTimeIsReadOnceWithTheMessage() {
        let sendInfo = TimelineItemSendInfo(timelineItem: ownMessage(), adjustedDeliveryStatus: nil, deliveryStatus: .sent)
        
        #expect(sendInfo.isReadWithMessage)
        #expect(sendInfo.isAccessibilityHidden)
    }
    
    @Test
    func aFailedSendKeepsItsMarkAndItsTimeInTheBubble() {
        let sendInfo = TimelineItemSendInfo(timelineItem: ownMessage(),
                                            adjustedDeliveryStatus: .sendingFailed(.unknown(reason: nil)),
                                            deliveryStatus: nil)
        
        #expect(sendInfo.showsFailureMark)
        #expect(sendInfo.layoutType == .overlay(capsuleStyle: false))
        #expect(!sendInfo.isTappable) // The mark and the label under the bubble are what's tapped.
    }
    
    @Test
    func everythingYouSendIsBlue() {
        let reply = TimelineItemReplyDetails.loaded(sender: .init(id: person.userID),
                                                    eventID: "$reply",
                                                    eventContent: .message(.text(.init(body: "Test"))))
        
        #expect(ownImage(caption: "The jetty").ownBubbleInk == .solid)
        #expect(ownImage(caption: nil, properties: .init(replyDetails: reply)).ownBubbleInk == .solid)
        #expect(ownImage(caption: nil, properties: .init(isThreaded: true)).ownBubbleInk == .solid)
        #expect(ownVideo(properties: .init(replyDetails: reply)).ownBubbleInk == .solid)
        #expect(ownGallery(caption: "The trip").ownBubbleInk == .solid)
        #expect(ownGallery(caption: nil, properties: .init(replyDetails: reply)).ownBubbleInk == .solid)
        #expect(ownLocation(geoURI: .init(latitude: 41.9, longitude: 12.5), properties: .init(replyDetails: reply)).ownBubbleInk == .solid)
        #expect(ownLocation(geoURI: nil, properties: .init()).ownBubbleInk == .solid)
        #expect(ownMessage().ownBubbleInk == .solid)
        #expect(PollRoomTimelineItem.mock(poll: .disclosed(createdByAccountOwner: true), isOutgoing: true, isEditable: false).ownBubbleInk == .solid)
    }
    
    @Test
    func aMessageThatCantBeShownIsHollow() {
        let redacted = RedactedRoomTimelineItem(id: .randomEvent,
                                                body: "Removed",
                                                timestamp: .mock,
                                                isOutgoing: true,
                                                isEditable: false,
                                                canBeRepliedTo: false,
                                                sender: .init(id: person.userID))
        #expect(redacted.ownBubbleInk == .hollow)
    }
    
    @Test
    func onlyAnOwnBubbleHasAnInk() {
        #expect(ownImage(caption: nil).ownBubbleInk == nil) // A photo alone has no bubble.
        #expect(ownLocation(geoURI: .init(latitude: 41.9, longitude: 12.5), properties: .init()).ownBubbleInk == nil)
        let incoming = TextRoomTimelineItem(id: .randomEvent,
                                            timestamp: .mock,
                                            isOutgoing: false,
                                            isEditable: false,
                                            canBeRepliedTo: true,
                                            sender: .init(id: person.userID),
                                            content: .init(body: "Hello"))
        #expect(incoming.ownBubbleInk == nil)
    }
    
    @Test
    func aPictureReachesItsBubblesEdges() {
        #expect(ownImage(caption: "The jetty").pictureReachesEdges)
        #expect(ownGallery(caption: "The trip").pictureReachesEdges)
        #expect(ownLocation(geoURI: .init(latitude: 41.9, longitude: 12.5), properties: .init()).pictureReachesEdges)
        #expect(!ownLocation(geoURI: nil, properties: .init()).pictureReachesEdges)
        #expect(!ownMessage().pictureReachesEdges)
    }
    
    // MARK: - Helpers
    
    /// What the row shows, from the context the view model gave it.
    private func deliveryStatus(of message: TextRoomTimelineItem,
                                in viewModel: TimelineViewModel,
                                adjustedDeliveryStatus: TimelineItemDeliveryStatus? = nil) -> TimelineDeliveryStatusView.Status? {
        viewModel.state.timelineState.itemsDictionary[message.id.uniqueID]?.rowContext.deliveryStatus(of: message, adjustedDeliveryStatus: adjustedDeliveryStatus)
    }
    
    private func ownImage(caption: String?, properties: RoomTimelineItemProperties = .init()) -> ImageRoomTimelineItem {
        ImageRoomTimelineItem(id: .randomEvent,
                              timestamp: .mock,
                              isOutgoing: true,
                              isEditable: false,
                              canBeRepliedTo: true,
                              sender: .init(id: RoomMemberProxyMock.mockMe.userID),
                              content: .init(filename: "jetty.jpg", caption: caption, imageInfo: .mockImage, thumbnailInfo: nil),
                              properties: properties)
    }
    
    private func ownVideo(properties: RoomTimelineItemProperties) -> VideoRoomTimelineItem {
        VideoRoomTimelineItem(id: .randomEvent,
                              timestamp: .mock,
                              isOutgoing: true,
                              isEditable: false,
                              canBeRepliedTo: true,
                              sender: .init(id: RoomMemberProxyMock.mockMe.userID),
                              content: .init(filename: "jetty.mp4", videoInfo: .mockVideo, thumbnailInfo: .mockVideoThumbnail),
                              properties: properties)
    }
    
    private func ownGallery(caption: String?, properties: RoomTimelineItemProperties = .init()) -> GalleryRoomTimelineItem {
        GalleryRoomTimelineItem(id: .randomEvent,
                                timestamp: .mock,
                                isOutgoing: true,
                                isEditable: false,
                                canBeRepliedTo: true,
                                sender: .init(id: RoomMemberProxyMock.mockMe.userID),
                                content: .init(body: "Gallery", caption: caption, items: []),
                                properties: properties)
    }
    
    private func ownLocation(geoURI: GeoURI?, properties: RoomTimelineItemProperties) -> LocationRoomTimelineItem {
        LocationRoomTimelineItem(id: .randomEvent,
                                 timestamp: .mock,
                                 isOutgoing: true,
                                 isEditable: false,
                                 canBeRepliedTo: true,
                                 sender: .init(id: RoomMemberProxyMock.mockMe.userID),
                                 content: .init(body: "The jetty", geoURI: geoURI),
                                 properties: properties)
    }
    
    private func ownMessage(id: TimelineItemIdentifier = .randomEvent, isOutgoing: Bool = true, receipts: [String] = []) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: id,
                             timestamp: .mock,
                             isOutgoing: isOutgoing,
                             isEditable: true,
                             canBeRepliedTo: true,
                             sender: .init(id: RoomMemberProxyMock.mockMe.userID),
                             content: .init(body: "Test"),
                             properties: .init(orderedReadReceipts: receipts.map { .init(userID: $0, formattedTimestamp: nil) }))
    }
    
    private func makeViewModel(timelineItems: [RoomTimelineItemProtocol],
                               heroes: [RoomMemberProxyMock] = [],
                               isDirect: Bool = false,
                               sharePresence: Bool = true) -> TimelineViewModel {
        makeViewModel(timelineController: TimelineControllerMock(.init(timelineItems: timelineItems)),
                      heroes: heroes,
                      isDirect: isDirect,
                      sharePresence: sharePresence)
    }
    
    private func makeViewModel(timelineController: TimelineControllerMock,
                               heroes: [RoomMemberProxyMock] = [],
                               isDirect: Bool = false,
                               sharePresence: Bool = true) -> TimelineViewModel {
        let userSettings = UserSettings.mock()
        userSettings.account.sharePresence = sharePresence
        return TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init(name: "",
                                                                      isDirect: isDirect,
                                                                      members: [.mockMe, person],
                                                                      heroes: heroes)),
                                 timelineController: timelineController,
                                 userSession: UserSessionMock(.init(userSettings: userSettings)),
                                 mediaPlayerProvider: MediaPlayerProviderMock(),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appMediator: AppMediatorMock(.init()),
                                 analyticsService: AnalyticsServiceMock(.init()),
                                 emojiProvider: EmojiProvider(userSettings: userSettings),
                                 linkMetadataProvider: LinkMetadataProvider(),
                                 timelineControllerFactory: TimelineControllerFactoryMock(.init()))
    }
}
