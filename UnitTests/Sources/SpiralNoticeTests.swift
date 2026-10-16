//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0073 — client-rendered notices.
//

@testable import ElementX
import Foundation
import Testing

struct SpiralNoticeTests {
    private let referral = #"{"com.spiral.notice":{"kind":"referral_joined","joined_user_id":"@diana:spiral.md"}}"#
    
    @Test
    func readsTheReferralNotice() throws {
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: referral))
        #expect(notice.kind == .referralJoined(joinedUserID: "@diana:spiral.md", joinedDisplayName: nil))
        #expect(notice.plainText == UntranslatedL10n.noticeReferralJoined("@diana:spiral.md"))
    }
    
    // Brief 0073 re-run: the card names the person, not the MXID, when the
    // server could read their profile.
    @Test
    func theReferralNoticeNamesTheNewcomer() throws {
        let data = #"{"com.spiral.notice":{"kind":"referral_joined","joined_user_id":"@diana:spiral.md","joined_display_name":"Diana"}}"#
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: data))
        #expect(notice.kind == .referralJoined(joinedUserID: "@diana:spiral.md", joinedDisplayName: "Diana"))
        #expect(notice.plainText == UntranslatedL10n.noticeReferralJoined("Diana"))
        
        let blank = #"{"com.spiral.notice":{"kind":"referral_joined","joined_user_id":"@diana:spiral.md","joined_display_name":"  "}}"#
        #expect(try #require(SpiralNotice(msgtype: "com.spiral.notice", data: blank)).plainText == UntranslatedL10n.noticeReferralJoined("@diana:spiral.md"))
    }
    
    @Test
    func readsTheWelcome() throws {
        let data = #"{"com.spiral.notice":{"kind":"welcome","owner_display_name":"Alice","agent_display_name":"Alice's Assistant","behavior":"personal_assistant"}}"#
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: data))
        #expect(notice.kind == .welcome(ownerDisplayName: "Alice", agentDisplayName: "Alice's Assistant", behavior: "personal_assistant"))
        #expect(notice.plainText == UntranslatedL10n.noticeWelcomeTitle("Alice"))
        // A welcome without names is not one.
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"welcome","owner_display_name":"Alice"}}"#) == nil)
    }
    
    // Brief 0075.
    @Test
    func readsThePhraseChangedNotice() throws {
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"phrase_changed","device_name":"Spiral на iPhone 15"}}"#))
        #expect(notice.kind == .phraseChanged(deviceName: "Spiral на iPhone 15"))
        #expect(notice.plainText == UntranslatedL10n.noticePhraseChangedTitle)
        // Cards posted before the device was known, or with a blank name.
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"phrase_changed"}}"#)?.kind == .phraseChanged(deviceName: nil))
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"phrase_changed","device_name":"  "}}"#)?.kind == .phraseChanged(deviceName: nil))
    }
    
    // Brief 0079 — the notices the server used to write in English.
    @Test
    func readsTheReplyFailedNotice() throws {
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"reply_failed"}}"#))
        #expect(notice.kind == .replyFailed)
        #expect(notice.plainText == UntranslatedL10n.noticeReplyFailedTitle)
    }
    
    // Coverage walk F7: a reply the content check held back is its own card, not "send it again".
    @Test
    func readsTheReplyWithheldNotice() throws {
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"reply_withheld"}}"#))
        #expect(notice.kind == .replyWithheld)
        #expect(notice.kind.wireName == "reply_withheld")
        #expect(notice.plainText == UntranslatedL10n.noticeReplyWithheldTitle)
        #expect(!UntranslatedL10n.noticeReplyWithheldBody.localizedCaseInsensitiveContains("again"))
    }
    
    @Test
    func readsTheBudgetNoticeAndItsResetTime() throws {
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice",
                                               data: #"{"com.spiral.notice":{"kind":"ai_budget_reached","resets_at":"2026-10-11T00:00:00Z"}}"#))
        #expect(notice.kind == .aiBudgetReached(resetsAt: Date(timeIntervalSince1970: 1_791_676_800)))
        // A reset time it cannot read is no budget notice.
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"ai_budget_reached","resets_at":"tomorrow"}}"#) == nil)
    }
    
    @Test
    func readsThePassAlongNoticeWithTheOwnersGreetingOnlyWhenWritten() throws {
        let plain = try #require(SpiralNotice(msgtype: "com.spiral.notice",
                                              data: #"{"com.spiral.notice":{"kind":"message_passed_to_owner","owner_display_name":"Alice"}}"#))
        #expect(plain.kind == .messagePassedToOwner(ownerDisplayName: "Alice", greeting: nil))
        let greeted = try #require(SpiralNotice(msgtype: "com.spiral.notice",
                                                data: #"{"com.spiral.notice":{"kind":"message_passed_to_owner","owner_display_name":"Alice","greeting":" Привіт! "}}"#))
        #expect(greeted.kind == .messagePassedToOwner(ownerDisplayName: "Alice", greeting: "Привіт!"))
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"message_passed_to_owner"}}"#) == nil)
    }
    
    @Test
    func readsTheIntroSuggestion() throws {
        let data = #"{"com.spiral.notice":{"kind":"intro_suggestion","candidate_agent_mxid":"@assistant-carlos:spiral.md","summary":"Builds iOS tools.","suggested_opener":"Hi Carlos!"}}"#
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: data))
        #expect(notice.kind == .introSuggestion(candidateAgentID: "@assistant-carlos:spiral.md", summary: "Builds iOS tools.", suggestedOpener: "Hi Carlos!"))
        #expect(notice.plainText == UntranslatedL10n.noticeIntroSuggestionTitle)
        #expect(SpiralNotice(msgtype: "com.spiral.notice",
                             data: #"{"com.spiral.notice":{"kind":"intro_suggestion","candidate_agent_mxid":"carlos","summary":"x","suggested_opener":"y"}}"#) == nil)
    }
    
    @Test
    func readsTheMovedToDMNotices() throws {
        let summary = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"summary_moved_to_dm","room_id":"!call:spiral.md"}}"#))
        #expect(summary.kind == .summaryMovedToDM(roomID: "!call:spiral.md"))
        let recording = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"recording_moved_to_dm","room_id":"!call:spiral.md"}}"#))
        #expect(recording.kind == .recordingMovedToDM(roomID: "!call:spiral.md"))
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"summary_moved_to_dm"}}"#) == nil)
    }
    
    // Decision 38 — `messenger.dm_owner`'s note, as `domain/notice.rs` writes it.
    private let relayed = #"{"com.spiral.notice":{"kind":"relayed_to_owner","note":"Bob will be late.","from_user_id":"@bob:spiral.md","room_id":"!dm:spiral.md"}}"#
    
    /// The note is the room-list preview, the push and the reply quote: never
    /// the fallback `body`, which ends with the sender's MXID and the room ID.
    @Test
    func aRelayedNoteReadsAsTheNote() throws {
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice", data: relayed))
        #expect(notice.kind == .relayedToOwner(note: "Bob will be late.", fromUserID: "@bob:spiral.md", roomID: "!dm:spiral.md"))
        #expect(notice.plainText == "Bob will be late.")
    }
    
    @Test
    func aRelayedNoteNeedsItsNoteSenderAndRoom() {
        let incomplete = [
            #"{"kind":"relayed_to_owner","note":"  ","from_user_id":"@bob:spiral.md","room_id":"!dm:spiral.md"}"#,
            #"{"kind":"relayed_to_owner","from_user_id":"@bob:spiral.md","room_id":"!dm:spiral.md"}"#,
            #"{"kind":"relayed_to_owner","note":"Hi","from_user_id":"bob","room_id":"!dm:spiral.md"}"#,
            #"{"kind":"relayed_to_owner","note":"Hi","from_user_id":"@bob:spiral.md"}"#
        ]
        for facts in incomplete {
            #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":"# + facts + "}") == nil, "\(facts)")
        }
    }
    
    /// Who: the owner themself, a name, or the MXID until the name is known.
    @Test
    func aRelayedNoteSaysWhoItIsFrom() {
        #expect(SpiralNoticeRoomTimelineView.relayedTitle(fromUserID: "@bob:spiral.md", ownUserID: "@alice:spiral.md", displayName: "Bob")
            == UntranslatedL10n.noticeRelayedToOwnerTitle("Bob"))
        #expect(SpiralNoticeRoomTimelineView.relayedTitle(fromUserID: "@bob:spiral.md", ownUserID: "@alice:spiral.md", displayName: nil)
            == UntranslatedL10n.noticeRelayedToOwnerTitle("@bob:spiral.md"))
        #expect(SpiralNoticeRoomTimelineView.relayedTitle(fromUserID: "@alice:spiral.md", ownUserID: "@alice:spiral.md", displayName: "Alice")
            == UntranslatedL10n.noticeRelayedToOwnerTitleYou)
    }
    
    /// Where: the room by name when the owner is in it, never its ID.
    @Test
    func aRelayedNoteSaysWhereItWasSaid() {
        #expect(SpiralNoticeRoomTimelineView.relayedRoomLine(roomName: "Book club") == UntranslatedL10n.noticeRelayedToOwnerRoom("Book club"))
        #expect(SpiralNoticeRoomTimelineView.relayedRoomLine(roomName: nil) == UntranslatedL10n.noticeRelayedToOwnerRoomUnknown)
        #expect(SpiralNoticeRoomTimelineView.relayedRoomLine(roomName: " ") == UntranslatedL10n.noticeRelayedToOwnerRoomUnknown)
        #expect(!SpiralNoticeRoomTimelineView.relayedRoomLine(roomName: nil).contains("!"))
    }
    
    /// Decision 150: to a person without AI consent, from the assistant they wrote to.
    @Test
    func readsTheAIConsentNotice() throws {
        let notice = try #require(SpiralNotice(msgtype: "com.spiral.notice",
                                               data: #"{"com.spiral.notice":{"kind":"ai_consent_needed","agent_display_name":"Alice's Assistant"}}"#))
        #expect(notice.plainText == UntranslatedL10n.noticeAiConsentNeededTitle)
        #expect(notice.kind == .aiConsentNeeded(agentDisplayName: "Alice's Assistant"))
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"ai_consent_needed"}}"#) == nil)
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"ai_consent_needed","agent_display_name":" "}}"#) == nil)
    }
    
    /// Someone who has allowed AI since, or another reader who has, is not asked to.
    @Test
    func theAIConsentNoticeAsksOnlyWhileAIIsNotAllowed() {
        #expect(SpiralNoticeRoomTimelineView.aiConsentBody(agentName: "Emmm", readerAllowsAI: false) == UntranslatedL10n.noticeAiConsentNeededBody("Emmm"))
        #expect(SpiralNoticeRoomTimelineView.aiConsentBody(agentName: "Emmm", readerAllowsAI: nil) == UntranslatedL10n.noticeAiConsentNeededBody("Emmm"))
        #expect(SpiralNoticeRoomTimelineView.aiConsentBody(agentName: "Emmm", readerAllowsAI: true) == UntranslatedL10n.noticeAiConsentNeededAllowedBody("Emmm"))
    }
    
    /// Review C1: a link in a message (`<a href="spiral:///settings/ai">`)
    /// reaches the app's URL parsing; no URL may open Settings.
    @Test
    func noLinkOpensTheAIToggle() throws {
        let parser = AppRouteURLParser(appSettings: AppSettings.volatile())
        #expect(try parser.route(from: #require(URL(string: "spiral:///settings/ai"))) == nil)
        #expect(try parser.route(from: #require(URL(string: "https://spiral.md/settings/ai"))) == nil)
    }
    
    /// The card's own action is the one way there: the timeline passes it on.
    @Test @MainActor
    func theAIConsentNoticeAsksForTheAIToggle() async throws {
        let appSettings = AppSettings.volatile()
        let viewModel = TimelineViewModel(roomProxy: JoinedRoomProxyMock(.init(name: "")),
                                          timelineController: TimelineControllerMock(.init()),
                                          userSession: UserSessionMock(.init()),
                                          mediaPlayerProvider: MediaPlayerProviderMock(),
                                          userIndicatorController: UserIndicatorControllerMock(),
                                          appMediator: AppMediatorMock(.init()),
                                          appSettings: appSettings,
                                          analyticsService: AnalyticsServiceMock(.init()),
                                          emojiProvider: EmojiProvider(appSettings: appSettings),
                                          linkMetadataProvider: LinkMetadataProvider(),
                                          timelineControllerFactory: TimelineControllerFactoryMock(.init()))
        let asked = deferFulfillment(viewModel.actions) { action in
            if case .displayAIConsentSettings = action { return true }
            return false
        }
        viewModel.context.send(viewAction: .openAIConsentSettings)
        try await asked.fulfill()
    }
    
    @Test
    func anotherMsgtypeIsNotANotice() {
        #expect(SpiralNotice(msgtype: "com.example.thing", data: referral) == nil)
    }
    
    @Test
    func unknownKindsAndMissingVariablesFallBackToTheBody() {
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"something_new"}}"#) == nil)
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: #"{"com.spiral.notice":{"kind":"referral_joined"}}"#) == nil)
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: "{}") == nil)
        #expect(SpiralNotice(msgtype: "com.spiral.notice", data: "not json") == nil)
    }
    
    @Test
    func theWelcomeNamesTheAssistantAsItIsCalledNow() {
        let renamed = TimelineItemSender(id: "@assistant-alice:spiral.md", displayName: "Olena Helper")
        #expect(SpiralNoticeRoomTimelineView.liveName(sender: renamed, fallback: "Alice's Assistant") == "Olena Helper")
        let loading = TimelineItemSender(id: "@assistant-alice:spiral.md", displayName: nil)
        #expect(SpiralNoticeRoomTimelineView.liveName(sender: loading, fallback: "Alice's Assistant") == "Alice's Assistant")
        let blank = TimelineItemSender(id: "@assistant-alice:spiral.md", displayName: "  ")
        #expect(SpiralNoticeRoomTimelineView.liveName(sender: blank, fallback: "Alice's Assistant") == "Alice's Assistant")
    }
}
