//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 357): every way a message can look in a chat, section by section, so that
// the look of a kind is chosen with all the others in view. A preview only: nothing here reaches the app.
//

import Compound
import LinkPresentation
import MatrixRustSDK
import SwiftUI

// A picture to choose from, not a gate: it has no references, and the audit fails on rows it draws side by side, such as
// the time on a photo. To render the sheets again, add `TestablePreview, SpiralGatedPreview` to the three previews and run
// `run-preview-tests.sh` for them, without committing that. They're three because one test has a time limit.

struct SpiralMessageCatalogText_Previews: PreviewProvider {
    static var previews: some View {
        SpiralMessageCatalog.text
    }
}

struct SpiralMessageCatalogMedia_Previews: PreviewProvider {
    static var previews: some View {
        SpiralMessageCatalog.media
    }
}

struct SpiralMessageCatalogEvents_Previews: PreviewProvider {
    static var previews: some View {
        SpiralMessageCatalog.events
    }
}

enum SpiralMessageCatalog {
    static let groupViewModel = makeViewModel(isDirect: false)
    static let directViewModel = makeViewModel(isDirect: true)
    static let unsafeViewModel = makeViewModel(isDirect: false, contentScannerService: ContentScannerServiceMock(.init(scanResult: false)))
    
    @ViewBuilder
    static var text: some View {
        section("Text", groupViewModel) { textSection }
        section("Formatted text", groupViewModel) { formattedTextSection }
        section("Replies and threads", groupViewModel) { repliesSection }
        section("Reactions and sending", groupViewModel) { statesSection }
        section("Removed and unreadable", groupViewModel) { unreadableSection }
        section("In a DM", directViewModel) { directSection }
        section("Own side only", groupViewModel) { ownSideSection }
    }
    
    @ViewBuilder
    static var media: some View {
        section("Photos", groupViewModel) { photosSection }
        section("Videos", groupViewModel) { videosSection }
        section("Galleries of photos and videos", groupViewModel) { mediaGalleriesSection }
        section("Galleries of files", groupViewModel) { fileGalleriesSection }
        section("Files", groupViewModel) { filesSection }
        section("Audio", groupViewModel) { audioSection }
        section("Voice messages", groupViewModel) { voiceSection }
    }
    
    @ViewBuilder
    static var events: some View {
        section("Locations", groupViewModel) { locationsSection }
        section("Polls", groupViewModel) { pollsSection }
        section("Interactive Posts", groupViewModel) { postsSection }
        section("Drafts and stickers", groupViewModel) { draftsSection }
        section("A generating card", groupViewModel) {
            label("While it works (only an agent sends one)")
            InteractiveGeneratingRoomTimelineView(timelineItem: generating(isFresh: true))
        }
        section("Calls in a group", groupViewModel) { groupCallsSection }
        section("Calls in a DM", directViewModel) { directCallsSection }
        section("Notices and emotes", groupViewModel) { noticesSection }
        section("Room events", groupViewModel) { roomEventsSection }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private static var textSection: some View {
        pair("Short") { text("See you at eight", own: $0) }
        pair("Long") { text(longText, own: $0) }
        pair("Emoji only") { text("🎉😂", own: $0, shouldBoost: true) }
        pair("A link") { html(#"Tickets are on <a href="https://spiral.md/tickets">spiral.md/tickets</a>"#, own: $0) }
        pair("A link preview") { own in
            RoomTimelineItemView(viewState: .init(item: textItem("The programme is out: https://spiral.md/programme",
                                                                 formatted: #"The programme is out: <a href="\#(linkPreviewURL.absoluteString)">\#(linkPreviewURL.absoluteString)</a>"#,
                                                                 own: own),
                                                  groupStyle: .single))
        }
    }
    
    @ViewBuilder
    private static var formattedTextSection: some View {
        pair("Code") { html("<p>This fixes it:</p><pre><code>let total = items.map(\\.price).reduce(0, +)</code></pre>", own: $0) }
        pair("Inline code") { html("Run <code>just ci</code> before you merge", own: $0) }
        pair("A quote") { html("<blockquote>The best time to plant a tree was twenty years ago.</blockquote><p>The second best is now</p>", own: $0) }
        pair("A list") { html("<ul><li>Bread</li><li>Olives</li><li>Two lemons</li></ul>", own: $0) }
        pair("A numbered list") { html("<ol><li>Pack</li><li>Lock up</li><li>Leave</li></ol>", own: $0) }
        pair("A mention") { html(#"<a href="https://matrix.to/#/@helena:spiral.md">@helena:spiral.md</a> could you check this?"#, own: $0) }
        label("A mention's pill alone (a snapshot leaves its place in the text blank)")
        mentionPill
        pair("Bold and italics") { html("That is <b>not</b> what she <i>said</i>", own: $0) }
        pair("Edited") { text("See you at nine", own: $0, properties: .init(isEdited: true)) }
        pair("Right to left") { text("נתראה בשמונה בערב", own: $0) }
        pair("Right to left, with a Latin word") { text("רואים אותך ב-Spiral הערב", own: $0) }
    }
    
    @ViewBuilder
    private static var repliesSection: some View {
        pair("A reply to text") { text("Eight works", own: $0, properties: reply(textContent)) }
        pair("A reply to a photo") { text("Where is this?", own: $0, properties: reply(photoContent)) }
        pair("A reply to a file") { text("Page 3 is wrong", own: $0, properties: reply(fileContent)) }
        pair("A reply to a voice message") { text("Heard it, thanks", own: $0, properties: reply(voiceContent)) }
        pair("A thread mark") { text("Replying in the thread", own: $0, properties: .init(isThreaded: true)) }
        pair("A reply in a thread") { text("Yes, that one", own: $0, properties: reply(textContent, isThreaded: true)) }
        pair("The start of a thread") { text("Who is coming on Friday?", own: $0, properties: .init(threadSummary: threadSummary)) }
    }
    
    @ViewBuilder
    private static var photosSection: some View {
        pair("Plain") { image(own: $0) }
        pair("With a caption") { image(caption: "The view from the top", own: $0) }
        pair("With a reply") { image(own: $0, properties: reply(textContent)) }
        pair("With a thread mark") { image(own: $0, properties: .init(isThreaded: true)) }
    }
    
    @ViewBuilder
    private static var videosSection: some View {
        pair("Plain") { video(own: $0) }
        pair("With a caption") { video(caption: "Sound on", own: $0) }
        pair("With a reply") { video(own: $0, properties: reply(textContent)) }
        pair("With a thread mark") { video(own: $0, properties: .init(isThreaded: true)) }
    }
    
    @ViewBuilder
    private static var mediaGalleriesSection: some View {
        pair("Photos") { gallery(imageItems, own: $0) }
        pair("Photos with a caption") { gallery(imageItems, caption: "Sunday at the lake", own: $0) }
        pair("Videos") { gallery(videoItems, own: $0) }
        pair("Videos with a caption") { gallery(videoItems, caption: "Both takes", own: $0) }
    }
    
    @ViewBuilder
    private static var fileGalleriesSection: some View {
        pair("Files") { gallery(fileItems, own: $0) }
        pair("Files with a caption") { gallery(fileItems, caption: "Everything for the meeting", own: $0) }
        pair("Mixed, with a caption") { gallery(mixedItems, caption: "All of it", own: $0) }
    }
    
    @ViewBuilder
    private static var filesSection: some View {
        pair("Plain") { file(own: $0) }
        pair("With a caption") { file(caption: "The figures you asked for", own: $0) }
        pair("With a reply") { file(own: $0, properties: reply(textContent)) }
        pair("With a thread mark") { file(own: $0, properties: .init(isThreaded: true)) }
    }
    
    @ViewBuilder
    private static var audioSection: some View {
        pair("Plain") { audio(own: $0) }
        pair("With a caption") { audio(caption: "The mix from last night", own: $0) }
        pair("With a reply") { audio(own: $0, properties: reply(textContent)) }
        pair("With a thread mark") { audio(own: $0, properties: .init(isThreaded: true)) }
    }
    
    @ViewBuilder
    private static var voiceSection: some View {
        pair("Plain") { voice(own: $0) }
        pair("Part played") { voice(own: $0, progress: 0.4) }
        pair("With a reply") { voice(own: $0, properties: reply(textContent)) }
        pair("With a thread mark") { voice(own: $0, properties: .init(isThreaded: true)) }
    }
    
    @ViewBuilder
    private static var locationsSection: some View {
        pair("A map") { location(geoURI: rome, own: $0) }
        pair("A pin on a map") { location(geoURI: rome, kind: .pin, own: $0) }
        pair("A map with a reply") { location(geoURI: rome, own: $0, properties: reply(textContent)) }
        pair("No map") { location(geoURI: nil, own: $0) }
        pair("Live location") { liveLocation(isLive: true, geoURI: rome, own: $0) }
        pair("Live location, waiting for the first fix") { liveLocation(isLive: true, geoURI: nil, own: $0) }
        pair("Live location, ended") { liveLocation(isLive: false, geoURI: rome, own: $0) }
    }
    
    @ViewBuilder
    private static var pollsSection: some View {
        pair("A poll") { own in
            PollRoomTimelineView(timelineItem: poll(.disclosed(createdByAccountOwner: own), own: own))
        }
        pair("Hidden results") { own in
            PollRoomTimelineView(timelineItem: poll(.undisclosed(createdByAccountOwner: own), own: own))
        }
        pair("An ended poll") { own in
            PollRoomTimelineView(timelineItem: poll(.endedDisclosed, own: own))
        }
    }
    
    @ViewBuilder
    private static var postsSection: some View {
        pair("An Interactive Post, running") { runningPost(own: $0) }
        pair("An Interactive Post, before it runs") { own in
            InteractivePostRoomTimelineView(timelineItem: post(own: own), slot: SpiralAppSlot())
        }
        pair("A reply on a post") { runningPost(own: $0, properties: reply(textContent)) }
    }
    
    @ViewBuilder
    private static var draftsSection: some View {
        label("A draft that can't be published (only an agent sends one)")
        InteractiveDraftRoomTimelineView(timelineItem: draft)
        label("A generating card that was lost")
        InteractiveGeneratingRoomTimelineView(timelineItem: generating(isFresh: false))
        pair("A sticker") { sticker(own: $0) }
    }
    
    @ViewBuilder
    private static var groupCallsSection: some View {
        label("Ended")
        call(.tombstoned(outcome: .unclassified), isDM: false)
        label("Ended, joined")
        call(.tombstoned(outcome: .groupCall(duration: 754, ownUserJoined: true)), isDM: false)
        label("Ended, not joined")
        call(.tombstoned(outcome: .groupCall(duration: 754, ownUserJoined: false)), isDM: false)
        label("Going on now")
        call(.active(activeMembers: [helena.id, jacob.id], isJoined: false, callStartTimestamp: .mock), isDM: false)
        label("Going on now, joined")
        call(.active(activeMembers: [helena.id, me.id], isJoined: true, callStartTimestamp: .mock), isDM: false)
        label("The old call card")
        CallInviteRoomTimelineView()
    }
    
    @ViewBuilder
    private static var directCallsSection: some View {
        label("Ended, voice, incoming")
        call(.tombstoned(outcome: .answered(duration: 1458)), isDM: true)
        label("Ended, voice, own")
        call(.tombstoned(outcome: .answered(duration: 321)), isDM: true, own: true)
        label("Ended, video, incoming")
        call(.tombstoned(outcome: .answered(duration: 1458)), isDM: true, isVoiceCall: false)
        label("Missed")
        call(.tombstoned(outcome: .missed), isDM: true)
        label("Cancelled, own")
        call(.tombstoned(outcome: .cancelled), isDM: true, own: true)
        label("Declined by them")
        call(.tombstoned(outcome: .declined(byMe: false)), isDM: true, own: true)
        label("Declined by me")
        call(.tombstoned(outcome: .declined(byMe: true)), isDM: true)
        label("Going on now")
        call(.active(activeMembers: [helena.id], isJoined: false, callStartTimestamp: .mock), isDM: true)
    }
    
    @ViewBuilder
    private static var noticesSection: some View {
        pair("A notice") { notice(own: $0) }
        pair("An emote") { emote(own: $0) }
        label("An agent's notice: a welcome")
        spiralNotice(#"{"kind":"welcome","owner_display_name":"Alice","agent_display_name":"Alice's Assistant","behavior":"personal_assistant"}"#)
        label("An agent's notice: a reply failed")
        spiralNotice(#"{"kind":"reply_failed"}"#)
        label("An agent's notice: passed to the owner")
        spiralNotice(#"{"kind":"message_passed_to_owner","owner_display_name":"Alice"}"#)
    }
    
    @ViewBuilder
    private static var roomEventsSection: some View {
        label("A date separator")
        SeparatorRoomTimelineView(timelineItem: .init(id: .randomVirtual, timestamp: .mock))
        label("New messages from here")
        ReadMarkerRoomTimelineView()
        label("The start of a room")
        TimelineStartRoomTimelineView(timelineItem: .init(name: "Lunch"))
        label("A state change")
        StateRoomTimelineView(timelineItem: state("Helena Ortiz joined the room"))
        label("A longer state change")
        StateRoomTimelineView(timelineItem: state("Helena Ortiz changed the room's name to Lunch on Friday, and the room's topic with it"))
        label("Several, folded")
        CollapsibleRoomTimelineView(timelineItem: collapsedStates)
        label("Loading older messages")
        PaginationIndicatorRoomTimelineView()
    }
    
    @ViewBuilder
    private static var statesSection: some View {
        pair("Reactions") { text("Lunch at one?", own: $0, properties: .init(reactions: reactions)) }
        pair("Reactions on a photo") { image(own: $0, properties: .init(reactions: reactions)) }
        pair("Many reactions") { text("Lunch at one?", own: $0, properties: .init(reactions: manyReactions)) }
        label("Sending")
        text("On my way", own: true, properties: .init(deliveryStatus: .sending))
        label("Sent")
        text("On my way", own: true, properties: .init(deliveryStatus: .sent))
        label("Read")
        TextRoomTimelineView(timelineItem: readItem)
        label("Failed")
        text("On my way", own: true, properties: .init(deliveryStatus: .sendingFailed(.unknown(reason: nil))))
        label("Failed on a photo")
        image(own: true, properties: .init(deliveryStatus: .sendingFailed(.unknown(reason: nil))))
        label("A warning about who sent it")
        text("Is this you?", own: false, properties: .init(encryptionAuthenticity: .unsignedDevice(color: .red)))
        text("Is this you?", own: true, properties: .init(encryptionAuthenticity: .notGuaranteed(color: .gray)))
    }
    
    @ViewBuilder
    private static var unreadableSection: some View {
        pair("Removed") { redacted(own: $0) }
        pair("Can't be decrypted yet") { encrypted(L10n.commonWaitingForDecryptionKey, encryptionType: .unknown, own: $0) }
        pair("Sent before you joined") { own in
            encrypted(L10n.commonUnableToDecryptNoAccess, encryptionType: .megolmV1AesSha2(sessionID: "session", cause: .sentBeforeWeJoined), own: own)
        }
        pair("Unsupported") { unsupported(own: $0) }
        pair("Blocked by a content scan") { own in
            file(own: own)
                .environmentObject(unsafeViewModel.context)
                .environment(\.timelineContext, unsafeViewModel.context)
        }
    }
    
    /// A DM has no sender's name or avatar. The rest of a row is the same as in a group, so one row of each family.
    @ViewBuilder
    private static var directSection: some View {
        pair("Text") { text("See you at eight", own: $0) }
        pair("A reply") { text("Eight works", own: $0, properties: reply(textContent)) }
        pair("A photo with a caption") { image(caption: "The view from the top", own: $0) }
        pair("A file") { file(own: $0) }
        pair("A voice message") { voice(own: $0) }
        pair("A poll") { own in
            PollRoomTimelineView(timelineItem: poll(.disclosed(createdByAccountOwner: own), own: own))
        }
        pair("Reactions") { text("Lunch at one?", own: $0, properties: .init(reactions: reactions)) }
    }
    
    /// What differs between own bubbles in blue and own bubbles in grey, with nothing else around it.
    @ViewBuilder
    static var ownSideSection: some View {
        label("A reply to text")
        text("Eight works", own: true, properties: reply(textContent))
        label("A reply to a photo")
        text("Where is this?", own: true, properties: reply(photoContent))
        label("A reply to a file")
        text("Page 3 is wrong", own: true, properties: reply(fileContent))
        label("A reply to a voice message")
        text("Heard it, thanks", own: true, properties: reply(voiceContent))
        label("A file")
        file(own: true)
        label("A file with a caption")
        file(caption: "The figures you asked for", own: true)
        label("A file with a reply")
        file(own: true, properties: reply(textContent))
        label("Audio")
        audio(own: true)
        label("Audio with a caption")
        audio(caption: "The mix from last night", own: true)
        label("A voice message")
        voice(own: true)
        label("A voice message, part played")
        voice(own: true, progress: 0.4)
        label("A voice message with a reply")
        voice(own: true, properties: reply(textContent))
        label("A photo")
        image(own: true)
        label("A photo with a caption")
        image(caption: "The view from the top", own: true)
        label("A photo with a reply")
        image(own: true, properties: reply(textContent))
        label("A video with a caption")
        video(caption: "Sound on", own: true)
        label("A gallery with a caption")
        gallery(imageItems, caption: "Sunday at the lake", own: true)
        label("A gallery of files")
        gallery(fileItems, own: true)
        label("A map")
        location(geoURI: rome, own: true)
        label("A map with a reply")
        location(geoURI: rome, own: true, properties: reply(textContent))
        label("A location with no map")
        location(geoURI: nil, own: true)
        label("A poll")
        PollRoomTimelineView(timelineItem: poll(.disclosed(createdByAccountOwner: true), own: true))
        label("An ended poll")
        PollRoomTimelineView(timelineItem: poll(.endedDisclosed, own: true))
        label("An Interactive Post")
        runningPost(own: true)
        label("A link, a list, code and a quote")
        html(#"Tickets are on <a href="https://spiral.md/tickets">spiral.md/tickets</a>"#, own: true)
        html("<ul><li>Bread</li><li>Olives</li></ul>", own: true)
        html("<p>This fixes it:</p><pre><code>let total = 12</code></pre>", own: true)
        html("<blockquote>The second best time is now</blockquote><p>Agreed</p>", own: true)
        label("Reactions and a thread")
        text("Lunch at one?", own: true, properties: .init(reactions: reactions))
        text("Who is coming on Friday?", own: true, properties: .init(threadSummary: threadSummary))
        label("Read, sent, sending, failed")
        RoomTimelineItemView(viewState: .init(item: readItem, groupStyle: .single))
        text("Ok", own: true)
        text("Sending this", own: true, properties: .init(deliveryStatus: .sending))
        text("Not sent", own: true, properties: .init(deliveryStatus: .sendingFailed(.unknown(reason: nil))))
        label("An emote")
        emote(own: true)
        label("A notice")
        notice(own: true)
        label("Removed")
        redacted(own: true)
        label("Can't be decrypted yet")
        encrypted(L10n.commonWaitingForDecryptionKey, encryptionType: .unknown, own: true)
        label("Unsupported")
        unsupported(own: true)
    }
    
    // MARK: - Layout
    
    static func section(_ title: String, _ viewModel: TimelineViewModel, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.compound.headingMDBold)
                .foregroundStyle(.compound.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            content()
        }
        .padding(.vertical, 8)
        .chatBackground()
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
        .previewDisplayName(title)
        .previewLayout(.sizeThatFits)
    }
    
    private static func pair(_ title: String, @ViewBuilder row: (Bool) -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            label(title)
            row(false)
            row(true)
        }
    }
    
    private static func label(_ title: String) -> some View {
        Text(title)
            .font(.compound.bodyXSSemibold)
            .foregroundStyle(.compound.textSecondary)
            .chatBackgroundChip()
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }
    
    // MARK: - Text
    
    private static func text(_ body: String, own: Bool, shouldBoost: Bool = false, properties: RoomTimelineItemProperties = .init()) -> some View {
        TextRoomTimelineView(timelineItem: textItem(body, own: own, shouldBoost: shouldBoost, properties: properties))
    }
    
    private static func html(_ html: String, own: Bool) -> some View {
        TextRoomTimelineView(timelineItem: textItem("", formatted: html, own: own))
    }
    
    private static func textItem(_ body: String,
                                 formatted: String? = nil,
                                 id: TimelineItemIdentifier = .randomEvent,
                                 own: Bool,
                                 shouldBoost: Bool = false,
                                 properties: RoomTimelineItemProperties = .init()) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: id,
                             timestamp: .mock,
                             isOutgoing: own,
                             isEditable: false,
                             canBeRepliedTo: true,
                             shouldBoost: shouldBoost,
                             sender: sender(own),
                             content: .init(body: body, formattedBody: formatted.flatMap(attributedStringBuilder.fromHTML)),
                             properties: properties)
    }
    
    /// A pill is a view inside `UITextView`, which a snapshot doesn't draw, so here it sits on the bubble by itself.
    private static var mentionPill: some View {
        VStack(spacing: 8) {
            pill.bubbleBackground(color: .compound._bgBubbleIncoming)
                .frame(maxWidth: .infinity, alignment: .leading)
            pill.environment(\.ownBubbleInk, .solid)
                .bubbleBackground(color: OwnBubbleStyle.fill)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private static var pill: some View {
        PillView(context: PillContext.mock(viewState: .mention(isOwnMention: false,
                                                               displayText: PillUtilities.userPillDisplayText(username: "Helena", userID: helena.id),
                                                               statusEmoji: nil))) { }
    }
    
    /// Read comes from a receipt in the timeline, which `makeViewModel` gives this item.
    private static var readItem: TextRoomTimelineItem {
        textItem("On my way",
                 id: .event(uniqueID: .init("read"), eventOrTransactionID: .eventID("$read")),
                 own: true,
                 properties: .init(orderedReadReceipts: [ReadReceipt(userID: helena.id, formattedTimestamp: nil)]))
    }
    
    // MARK: - Media
    
    private static func image(caption: String? = nil, own: Bool, properties: RoomTimelineItemProperties = .init()) -> some View {
        ImageRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                  timestamp: .mock,
                                                  isOutgoing: own,
                                                  isEditable: false,
                                                  canBeRepliedTo: true,
                                                  sender: sender(own),
                                                  content: .init(filename: "lake.jpg",
                                                                 caption: caption,
                                                                 imageInfo: .mockImage,
                                                                 thumbnailInfo: .mockThumbnail,
                                                                 blurhash: blurhash,
                                                                 contentType: .jpeg),
                                                  properties: properties))
    }
    
    private static func video(caption: String? = nil, own: Bool, properties: RoomTimelineItemProperties = .init()) -> some View {
        VideoRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                  timestamp: .mock,
                                                  isOutgoing: own,
                                                  isEditable: false,
                                                  canBeRepliedTo: true,
                                                  sender: sender(own),
                                                  content: .init(filename: "take-2.mp4",
                                                                 caption: caption,
                                                                 videoInfo: .mockVideo,
                                                                 thumbnailInfo: .mockVideoThumbnail,
                                                                 blurhash: blurhash),
                                                  properties: properties))
    }
    
    private static func gallery(_ items: [GalleryItem], caption: String? = nil, own: Bool) -> some View {
        GalleryRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                    timestamp: .mock,
                                                    isOutgoing: own,
                                                    isEditable: false,
                                                    canBeRepliedTo: true,
                                                    sender: sender(own),
                                                    content: .init(body: "Gallery", caption: caption, items: items),
                                                    properties: .init()))
    }
    
    private static func file(caption: String? = nil, own: Bool, properties: RoomTimelineItemProperties = .init()) -> some View {
        FileRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                 timestamp: .mock,
                                                 isOutgoing: own,
                                                 isEditable: false,
                                                 canBeRepliedTo: true,
                                                 sender: sender(own),
                                                 content: .init(filename: "budget-2026.pdf",
                                                                caption: caption,
                                                                source: try? MediaSourceProxy(url: .mockMXCFile, mimeType: nil),
                                                                fileSize: 3 * 1024 * 1024,
                                                                thumbnailSource: nil,
                                                                contentType: .pdf),
                                                 properties: properties))
    }
    
    private static func audio(caption: String? = nil, own: Bool, properties: RoomTimelineItemProperties = .init()) -> some View {
        AudioRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                  timestamp: .mock,
                                                  isOutgoing: own,
                                                  isEditable: false,
                                                  canBeRepliedTo: true,
                                                  sender: sender(own),
                                                  content: .init(filename: "live-at-the-lake.mp3",
                                                                 caption: caption,
                                                                 duration: 300,
                                                                 waveform: nil,
                                                                 source: try? MediaSourceProxy(url: .mockMXCAudio, mimeType: nil),
                                                                 fileSize: 7 * 1024 * 1024,
                                                                 contentType: nil),
                                                  properties: properties))
    }
    
    private static func voice(own: Bool, progress: Double = 0, properties: RoomTimelineItemProperties = .init()) -> some View {
        let id = TimelineItemIdentifier.randomEvent
        let item = VoiceMessageRoomTimelineItem(id: id,
                                                timestamp: .mock,
                                                isOutgoing: own,
                                                isEditable: false,
                                                canBeRepliedTo: true,
                                                sender: sender(own),
                                                content: .init(filename: "voice.ogg",
                                                               duration: 42,
                                                               waveform: EstimatedWaveform.mockWaveform,
                                                               source: try? MediaSourceProxy(url: .mockMXCAudio, mimeType: nil),
                                                               fileSize: nil,
                                                               contentType: nil),
                                                properties: properties)
        return VoiceMessageRoomTimelineView(timelineItem: item,
                                            playerState: AudioPlayerState(id: .timelineItemIdentifier(id),
                                                                          title: L10n.commonVoiceMessage,
                                                                          duration: 42,
                                                                          waveform: EstimatedWaveform.mockWaveform,
                                                                          progress: progress))
    }
    
    private static func sticker(own: Bool) -> some View {
        StickerRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                    body: "A sticker",
                                                    timestamp: .mock,
                                                    isOutgoing: own,
                                                    isEditable: false,
                                                    canBeRepliedTo: true,
                                                    sender: sender(own),
                                                    imageInfo: .init(source: ImageInfoProxy.mockImage.source, width: 160, height: 160, mimeType: nil, fileSize: nil),
                                                    blurhash: blurhash))
    }
    
    // MARK: - Locations and polls
    
    private static func location(geoURI: GeoURI?, kind: StaticLocationKind = .sender, own: Bool, properties: RoomTimelineItemProperties = .init()) -> some View {
        LocationRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                     timestamp: .mock,
                                                     isOutgoing: own,
                                                     isEditable: false,
                                                     canBeRepliedTo: true,
                                                     sender: sender(own),
                                                     content: .init(body: "Piazza Navona, Rome", geoURI: geoURI, kind: kind),
                                                     properties: properties))
    }
    
    private static func liveLocation(isLive: Bool, geoURI: GeoURI?, own: Bool) -> some View {
        LiveLocationRoomTimelineView(currentDate: .mock,
                                     timelineItem: .init(id: .randomEvent,
                                                         timestamp: .mock,
                                                         isOutgoing: own,
                                                         isEditable: false,
                                                         canBeRepliedTo: true,
                                                         sender: sender(own),
                                                         content: .init(isLive: isLive, timeoutDate: .mock.addingTimeInterval(600), lastGeoURI: geoURI)))
    }
    
    private static func poll(_ poll: Poll, own: Bool) -> PollRoomTimelineItem {
        PollRoomTimelineItem(id: .randomEvent,
                             poll: poll,
                             body: "poll",
                             timestamp: .mock,
                             isOutgoing: own,
                             isEditable: own,
                             canBeRepliedTo: true,
                             sender: sender(own),
                             properties: .init())
    }
    
    // MARK: - Posts
    
    /// A post's app runs in a web view, which a snapshot can't start, so the wheel of `InteractivePostTimeline_Previews` stands in for it.
    private static func runningPost(own: Bool, properties: RoomTimelineItemProperties = .init()) -> some View {
        let item = post(own: own, properties: properties)
        return TimelineStyler(timelineItem: item) {
            SpiralAppPostFrame(aspectRatio: item.post.displayAspectRatio,
                               isReady: true,
                               isLoading: false,
                               cardTitle: item.body,
                               cardSubtitle: item.body,
                               accessibilityLabel: item.body) {
                WheelStandIn()
            } expanded: {
                EmptyView()
            }
        }
    }
    
    private static func post(own: Bool, properties: RoomTimelineItemProperties = .init()) -> InteractivePostRoomTimelineItem {
        InteractivePostRoomTimelineItem(id: .randomEvent,
                                        body: "Where do we eat?",
                                        timestamp: .mock,
                                        isOutgoing: own,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: sender(own),
                                        post: SpiralAppPost(InteractivePostContent(body: "Where do we eat?",
                                                                                   appId: "wheel",
                                                                                   runtime: "1",
                                                                                   title: "Where do we eat?",
                                                                                   aspect: "16:9",
                                                                                   stateChannel: "matrix",
                                                                                   sha256: String(repeating: "a", count: 64),
                                                                                   url: "mxc://spiral.md/wheel",
                                                                                   fileJson: nil)),
                                        properties: properties)
    }
    
    /// One whose digest fails. A sound draft starts its app in a web view, which a snapshot waits on until it times out.
    private static var draft: InteractiveDraftRoomTimelineItem {
        InteractiveDraftRoomTimelineItem(id: .randomEvent,
                                         body: "Where do we eat?",
                                         timestamp: .mock,
                                         isOutgoing: false,
                                         isEditable: false,
                                         canBeRepliedTo: false,
                                         sender: helena,
                                         draft: SpiralAppDraft(InteractiveDraftContent(body: "Where do we eat?",
                                                                                       title: "Where do we eat?",
                                                                                       aspect: "16:9",
                                                                                       manifestJson: "{}",
                                                                                       source: "",
                                                                                       sha256: String(repeating: "0", count: 64),
                                                                                       version: 1,
                                                                                       generatedByAgentId: nil,
                                                                                       targetRoomId: nil)))
    }
    
    /// A fresh card is dated on a day to come, as in `InteractiveGeneratingRoomTimelineView_Previews`, so it's never stale
    /// and its time stays 9:41. A stale one is dated at `.mock`.
    private static func generating(isFresh: Bool) -> InteractiveGeneratingRoomTimelineItem {
        let timestamp = isFresh ? DateComponents(calendar: .current, year: 2100, month: 1, day: 9, hour: 9, minute: 41).date ?? .mock : .mock
        return InteractiveGeneratingRoomTimelineItem(id: .randomEvent,
                                                     body: "Creating draft v1…",
                                                     timestamp: timestamp,
                                                     isOutgoing: false,
                                                     isEditable: false,
                                                     canBeRepliedTo: false,
                                                     sender: helena)
    }
    
    // MARK: - Calls, notices and room events
    
    private static func call(_ state: CallNotificationRoomTimelineItem.CallState, isDM: Bool, own: Bool = false, isVoiceCall: Bool = true) -> some View {
        CallNotificationRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             sender: sender(own),
                                                             isDM: isDM,
                                                             isVoiceCall: isVoiceCall,
                                                             callState: state,
                                                             isOutgoing: own))
    }
    
    private static func notice(own: Bool) -> some View {
        NoticeRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                   timestamp: .mock,
                                                   isOutgoing: own,
                                                   isEditable: false,
                                                   canBeRepliedTo: true,
                                                   sender: sender(own),
                                                   content: .init(body: "The build finished in four minutes")))
    }
    
    private static func emote(own: Bool) -> some View {
        EmoteRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                  timestamp: .mock,
                                                  isOutgoing: own,
                                                  isEditable: false,
                                                  canBeRepliedTo: true,
                                                  sender: sender(own),
                                                  content: .init(body: "* \(sender(own).displayName ?? "") waves from the door")))
    }
    
    @ViewBuilder
    private static func spiralNotice(_ facts: String) -> some View {
        if let notice = SpiralNotice(msgtype: SpiralNotice.msgtype, data: #"{"com.spiral.notice":\#(facts)}"#) {
            SpiralNoticeRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                             timestamp: .mock,
                                                             sender: .init(id: "@assistant-alice:spiral.md", displayName: "Alice's Assistant"),
                                                             notice: notice))
        }
    }
    
    private static func state(_ body: String) -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: .randomEvent,
                              body: body,
                              timestamp: .mock,
                              isOutgoing: false,
                              isEditable: false,
                              canBeRepliedTo: false,
                              sender: helena)
    }
    
    private static var collapsedStates: CollapsibleTimelineItem {
        CollapsibleTimelineItem(items: [state("Helena Ortiz joined the room"), state("Jacob joined the room"), state("Jacob left the room")])
    }
    
    // MARK: - Removed and unreadable
    
    private static func redacted(own: Bool) -> some View {
        RedactedRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                     body: L10n.commonMessageRemoved,
                                                     timestamp: .mock,
                                                     isOutgoing: own,
                                                     isEditable: false,
                                                     canBeRepliedTo: false,
                                                     sender: sender(own)))
    }
    
    private static func encrypted(_ body: String, encryptionType: EncryptedRoomTimelineItem.EncryptionType, own: Bool) -> some View {
        EncryptedRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                      body: body,
                                                      encryptionType: encryptionType,
                                                      timestamp: .mock,
                                                      isOutgoing: own,
                                                      isEditable: false,
                                                      canBeRepliedTo: false,
                                                      sender: sender(own)))
    }
    
    private static func unsupported(own: Bool) -> some View {
        UnsupportedRoomTimelineView(timelineItem: .init(id: .randomEvent,
                                                        body: "Unsupported event",
                                                        eventType: "com.example.event",
                                                        error: "Not known here",
                                                        timestamp: .mock,
                                                        isOutgoing: own,
                                                        isEditable: false,
                                                        canBeRepliedTo: true,
                                                        sender: sender(own)))
    }
    
    // MARK: - Sample content
    
    private static let attributedStringBuilder = AttributedStringBuilder(cacheKey: "SpiralMessageCatalog", mentionBuilder: MentionBuilder())
    private static let blurhash = "L%KUc%kqS$RP?Ks,WEf8OlrqaekW"
    private static let rome = GeoURI(latitude: 41.902782, longitude: 12.496366)
    private static let longText = """
    The train leaves at seven, so we should meet on the platform by half past six. I'll bring the tickets and the sandwiches, \
    you bring the map. If anything changes, write here and I'll see it on the way.
    """
    
    private static let helena = TimelineItemSender(id: "@helena:spiral.md", displayName: "Helena Ortiz")
    private static let jacob = TimelineItemSender(id: "@jacob:spiral.md", displayName: "Jacob")
    private static let me = TimelineItemSender(id: RoomMemberProxyMock.mockMe.userID, displayName: "Me")
    
    private static func sender(_ own: Bool) -> TimelineItemSender {
        own ? me : helena
    }
    
    private static func reply(_ content: TimelineEventContent, isThreaded: Bool = false) -> RoomTimelineItemProperties {
        .init(replyDetails: .loaded(sender: jacob, eventID: "$replied", eventContent: content), isThreaded: isThreaded)
    }
    
    private static var textContent: TimelineEventContent {
        .message(.text(.init(body: "Does eight work for you?")))
    }
    
    private static var photoContent: TimelineEventContent {
        .message(.image(.init(filename: "lake.jpg",
                              caption: nil,
                              imageInfo: .mockImage,
                              thumbnailInfo: .mockThumbnail,
                              blurhash: blurhash,
                              contentType: .jpeg)))
    }
    
    private static var fileContent: TimelineEventContent {
        .message(.file(.init(filename: "budget-2026.pdf", source: nil, fileSize: 3 * 1024 * 1024, thumbnailSource: nil, contentType: .pdf)))
    }
    
    private static var voiceContent: TimelineEventContent {
        .message(.voice(.init(filename: "voice.ogg", duration: 42, waveform: nil, source: nil, fileSize: nil, contentType: nil)))
    }
    
    private static var threadSummary: TimelineItemThreadSummary {
        .loaded(senderID: jacob.id, sender: jacob, latestEventContent: .message(.text(.init(body: "I can make it after six"))), numberOfReplies: 3)
    }
    
    private static var reactions: [AggregatedReaction] {
        [AggregatedReaction(accountOwnerID: me.id, key: "👍", senders: [me, jacob].map { ReactionSender(id: $0.id, timestamp: .mock) }),
         AggregatedReaction(accountOwnerID: me.id, key: "🍕", senders: [ReactionSender(id: helena.id, timestamp: .mock)])]
    }
    
    private static var manyReactions: [AggregatedReaction] {
        ["👍", "❤️", "😂", "🎉", "🍕", "🔥", "👀", "🙏", "🥂"].map { key in
            AggregatedReaction(accountOwnerID: me.id, key: key, senders: [ReactionSender(id: helena.id, timestamp: .mock)])
        }
    }
    
    private static var imageItems: [GalleryItem] {
        (0..<3).map { .mockImage(index: $0, filename: "lake-\($0).jpg") }
    }
    
    private static var videoItems: [GalleryItem] {
        (0..<2).map { .mockVideo(index: $0, filename: "take-\($0).mp4") }
    }
    
    private static var fileItems: [GalleryItem] {
        [.mockFile(index: 0, filename: "agenda.pdf"), .mockFile(index: 1, filename: "budget-2026.pdf"), .mockFile(index: 2, filename: "minutes.pdf")]
    }
    
    private static var mixedItems: [GalleryItem] {
        [.mockImage(index: 0, filename: "lake.jpg"), .mockFile(index: 1, filename: "budget-2026.pdf"), .mockAudio(index: 2, filename: "meeting.m4a")]
    }
    
    // MARK: - View models
    
    private static let linkPreviewURL: URL = "https://spiral.md/programme"
    
    private static func makeViewModel(isDirect: Bool, contentScannerService: ContentScannerServiceProtocol? = nil) -> TimelineViewModel {
        let roomProxy = JoinedRoomProxyMock(.init(name: "Lunch",
                                                  isDirect: isDirect,
                                                  hasOngoingCall: false,
                                                  members: isDirect ? [.mockMe, .mockAlice] : [.mockMe, .mockAlice, .mockBob, .mockCharlie]))
        let userSettings = UserSettings.mock()
        userSettings.app.threadsEnabled = true
        userSettings.app.linkPreviewsEnabled = true
        userSettings.account.sharePresence = true
        
        return TimelineViewModel(roomProxy: roomProxy,
                                 timelineController: TimelineControllerMock(.init(timelineItems: [readItem])),
                                 userSession: UserSessionMock(.init(userSettings: userSettings, contentScannerService: contentScannerService)),
                                 mediaPlayerProvider: MediaPlayerProviderMock(),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appMediator: AppMediatorMock(.init()),
                                 analyticsService: AnalyticsServiceMock(.init()),
                                 emojiProvider: EmojiProvider(userSettings: userSettings),
                                 linkMetadataProvider: CatalogLinkMetadataProvider(url: linkPreviewURL),
                                 timelineControllerFactory: TimelineControllerFactoryMock(.init()))
    }
}

/// A link's preview with no network.
private final class CatalogLinkMetadataProvider: LinkMetadataProviderProtocol {
    let metadataItems: [URL: LinkMetadataProviderItem]
    
    init(url: URL) {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.url = url
        metadata.title = "The programme for Friday"
        metadataItems = [url: .init(metadata: metadata)]
    }
    
    func fetchMetadataFor(url: URL) async -> Result<LinkMetadataProviderItem, Error> {
        .success(metadataItems[url] ?? .init(metadata: nil))
    }
}
