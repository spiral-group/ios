//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Foundation
@testable import Spiral
import Testing

@MainActor
struct PillContextTests {
    @Test
    func user() async {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let id = "@test:matrix.org"
        let proxyMock = JoinedRoomProxyMock(.init(name: "Test"))
        let subject = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([])
        proxyMock.membersPublisher = subject.asCurrentValuePublisher()
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: TimelineControllerMock(.init()),
                                     userSession: UserSessionMock(.init()),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .user(userID: id), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(context.viewState.displayText == id)
        
        let name = "Mr. Test"
        let avatarURL = URL(string: "https://test.jpg")
        subject.send([RoomMemberProxyMock(with: .init(userID: id, displayName: name, avatarURL: avatarURL, membership: .join))])
        await Task.yield()
        
        #expect(!context.viewState.isOwnMention)
        #expect(context.viewState.displayText == "@\(name)")
    }
    
    @Test
    func ownUser() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let id = "@test:matrix.org"
        let proxyMock = JoinedRoomProxyMock(.init(name: "Test", ownUserID: id))
        let subject = CurrentValueSubject<[RoomMemberProxyProtocol], Never>([])
        proxyMock.membersPublisher = subject.asCurrentValuePublisher()
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: TimelineControllerMock(.init()),
                                     userSession: UserSessionMock(.init()),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .user(userID: id), font: .preferredFont(forTextStyle: .body)))
        
        #expect(context.viewState.isOwnMention)
    }
    
    @Test
    func allUsers() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let avatarURL = URL(string: "https://matrix.jpg")
        let id = "test_room"
        let displayName = "Test"
        let proxyMock = JoinedRoomProxyMock(.init(id: id, name: displayName, avatarURL: avatarURL))
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init()),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .allUsers, font: .preferredFont(forTextStyle: .body)))
        
        #expect(context.viewState.isOwnMention)
        #expect(context.viewState.displayText == PillUtilities.atRoom)
    }
    
    @Test
    func roomIDMention() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let clientMock = ClientProxyMock(.init())
        clientMock.roomSummaryForIdentifierReturnValue = .mock(id: "1", name: "Foundation 🔭🪐🌌")
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init(clientProxy: clientMock)),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .roomID("1"), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "#Foundation 🔭🪐🌌")
    }
    
    @Test
    func roomIDMentionMissingRoom() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init()),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .roomID("1"), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "1")
    }
    
    @Test
    func roomAliasMention() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let clientMock = ClientProxyMock(.init())
        clientMock.roomSummaryForAliasReturnValue = .mock(id: "2",
                                                          name: "Foundation and Empire",
                                                          canonicalAlias: "#foundation-and-empire:matrix.org")
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init(clientProxy: clientMock)),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .roomAlias("#foundation-and-empire:matrix.org"), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "#Foundation and Empire")
    }
    
    @Test
    func roomAliasMentionMissingRoom() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init()),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .roomAlias("#foundation-and-empire:matrix.org"), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "#foundation-and-empire:matrix.org")
    }
    
    @Test
    func eventOnRoomIDMention() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let clientMock = ClientProxyMock(.init())
        clientMock.roomSummaryForIdentifierReturnValue = .mock(id: "1", name: "Foundation 🔭🪐🌌")
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init(clientProxy: clientMock)),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .event(room: .roomID("1")), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "💬 > #Foundation 🔭🪐🌌")
    }
    
    @Test
    func eventOnRoomIDMentionMissingRoom() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init()),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .event(room: .roomID("1")), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "💬 > 1")
    }
    
    @Test
    func eventOnRoomAliasMention() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let clientMock = ClientProxyMock(.init())
        clientMock.roomSummaryForAliasReturnValue = .mock(id: "2",
                                                          name: "Foundation and Empire",
                                                          canonicalAlias: "#foundation-and-empire:matrix.org")
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init(clientProxy: clientMock)),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .event(room: .roomAlias("#foundation-and-empire:matrix.org")), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "💬 > #Foundation and Empire")
    }
    
    @Test
    func eventOnRoomAliasMentionMissingRoom() {
        let userIndicatorController = UserIndicatorControllerMock()
        
        let proxyMock = JoinedRoomProxyMock(.init())
        let mockController = TimelineControllerMock(.init(roomProxy: proxyMock))
        let mock = TimelineViewModel(roomProxy: proxyMock,
                                     timelineController: mockController,
                                     userSession: UserSessionMock(.init()),
                                     mediaPlayerProvider: MediaPlayerProviderMock(),
                                     userIndicatorController: userIndicatorController,
                                     appMediator: AppMediatorMock(.init()),
                                     analyticsService: AnalyticsServiceMock(.init()),
                                     emojiProvider: EmojiProvider(userSettings: .mock()),
                                     linkMetadataProvider: LinkMetadataProvider(),
                                     timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let context = PillContext(timelineContext: mock.context, data: PillTextAttachmentData(type: .event(room: .roomAlias("#foundation-and-empire:matrix.org")), font: .preferredFont(forTextStyle: .body)))
        
        #expect(!context.viewState.isOwnMention)
        #expect(!context.viewState.isUndefined)
        #expect(context.viewState.displayText == "💬 > #foundation-and-empire:matrix.org")
    }
    
    // AGENT-PLATFORM (1.0.3 B19): a tap on a pill or a matrix.to link in the plain composer opens nothing.
    @Test
    func aTappedPillInTheComposerOpensNothing() throws {
        let text = NSMutableAttributedString(string: "Hi @bob")
        let url = try #require(URL(string: "https://spiral.md/@bob:spiral.md"))
        MentionBuilder().handleUserMention(for: text, in: NSRange(location: 3, length: 4), url: url, userID: "@bob:spiral.md", userDisplayName: "Bob")
        let pill = NSRange(location: 3, length: 1)
        
        #expect(!MessageComposerTextField.opensTappedLink(url, in: text, range: pill))
        #expect(!MessageComposerTextField.opensTappedLink(nil, in: text, range: pill), "A pill without a link")
        #expect(!MessageComposerTextField.opensTappedLink(URL(string: "https://matrix.to/#/@bob:spiral.md"), in: text, range: NSRange(location: 0, length: 2)))
        #expect(MessageComposerTextField.opensTappedLink(URL(string: "https://example.org"), in: text, range: NSRange(location: 0, length: 2)),
                "Another link keeps its default")
        #expect(!MessageComposerTextField.opensTappedLink(url, in: text, range: NSRange(location: 2, length: 40)), "A range past the end is clamped")
    }
}
