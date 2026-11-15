//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 359 item 16): the chat the timeline benchmark measures. The same rows in the same
// order on every run: a seeded generator, fixed dates and no network, so two runs differ only in the code under test.
// Compiled only with SPIRAL_TIMELINE_BENCH, which Tools/Scripts/run-timeline-bench.sh passes and no project file sets.
//

#if SPIRAL_TIMELINE_BENCH

import Foundation
import MatrixRustSDK
import SwiftUI

/// One row of the fixture and the name it goes by in the results, finer than its type: a reply costs more than a plain message.
struct TimelineBenchRow {
    let item: RoomTimelineItemProtocol
    let kind: String
}

struct TimelineBenchFixture {
    /// The most rows a run may ask for. 100, 300 and 500 are the newest rows of the same chat, as a room opens at its end.
    static let maximumRowCount = 500

    static let helena = person("helena", "Helena Ortiz")
    static let jacob = person("jacob", "Jacob Weiss")
    static let marcus = person("marcus", "Marcus Lee")
    static let oksana = person("oksana", "Оксана Коваль")
    static let assistant = person("assistant-helena", "Helena's Assistant")
    static let me = TimelineItemSender(id: RoomMemberProxyMock.mockMe.userID, displayName: "Me", avatarURL: URL(string: "mxc://spiral.md/avatar-me"))
    static let people = [helena, jacob, marcus, oksana, assistant]

    /// A Saturday in the past: nothing here may depend on today, and every row is old enough that no card counts as fresh.
    private static let firstDay = Date(timeIntervalSince1970: 1_780_000_000)

    /// The digest of the post's container, when the run serves a real one.
    let postDigest: String

    /// The newest `count` rows of the chat.
    func rows(count: Int) -> [TimelineBenchRow] {
        var generator = Generator(postDigest: postDigest)
        return Array(generator.chat().suffix(count))
    }

    /// A deterministic incoming message, numbered from the end of the fixture.
    static func incomingMessage(_ number: Int) -> TextRoomTimelineItem {
        let sender = people[number % 3]
        return TextRoomTimelineItem(id: event("incoming-\(number)"),
                                    timestamp: firstDay.addingTimeInterval(60 * 60 * 24 * 40 + TimeInterval(number)),
                                    isOutgoing: false,
                                    isEditable: false,
                                    canBeRepliedTo: true,
                                    sender: sender,
                                    content: .init(body: Corpus.short[number % Corpus.short.count]))
    }

    static func reaction(_ key: String) -> AggregatedReaction {
        AggregatedReaction(accountOwnerID: me.id, key: key, senders: [ReactionSender(id: helena.id, timestamp: firstDay)])
    }

    fileprivate static func event(_ id: String) -> TimelineItemIdentifier {
        .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)"))
    }

    private static func person(_ name: String, _ displayName: String) -> TimelineItemSender {
        TimelineItemSender(id: "@\(name):spiral.md", displayName: displayName, avatarURL: URL(string: "mxc://spiral.md/avatar-\(name)"))
    }

    fileprivate static func date(minute: Int) -> Date {
        firstDay.addingTimeInterval(TimeInterval(minute) * 60)
    }
}

// MARK: - The chat

/// What a chat is made of, by how often each kind turns up in one. Everything a room draws, apart from locations (a map
/// needs the network) and link previews (they're off by default).
private enum Kind: String {
    case textShort = "text.short"
    case textLong = "text.long"
    case textFormatted = "text.formatted"
    case textEmoji = "text.emoji"
    case reply = "text.reply"
    case reactions = "text.reactions"
    case thread = "text.thread"
    case image
    case imageCaption = "image.caption"
    case gallery
    case video
    case file
    case audio
    case voice
    case call
    case notice = "card.notice"
    case draft = "card.draft"
    case generating = "card.generating"
    case state
    case group
    case poll
    case emote
    case noticeMessage = "text.notice"
    case redacted
    case encrypted
    case sticker
    case post

    static let weights: [(kind: Kind, weight: Int)] = [(.textShort, 380), (.textLong, 60), (.textFormatted, 50), (.textEmoji, 10),
                                                       (.reply, 90), (.reactions, 70), (.thread, 15),
                                                       (.image, 55), (.imageCaption, 20), (.gallery, 8), (.video, 12),
                                                       (.file, 25), (.audio, 6), (.voice, 30), (.call, 18),
                                                       (.notice, 8), (.draft, 3), (.generating, 3), (.state, 20), (.group, 8),
                                                       (.poll, 5), (.emote, 4), (.noticeMessage, 6), (.redacted, 8), (.encrypted, 6),
                                                       (.sticker, 4), (.post, 10)]
}

/// SplitMix64: a few lines, and the same sequence on every machine.
private struct SeededRandom {
    private var state: UInt64 = 0x5350_4952_414C_0359

    mutating func next(below bound: Int) -> Int {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Int(value % UInt64(bound))
    }

    mutating func chance(_ percent: Int) -> Bool {
        next(below: 100) < percent
    }
}

private struct Generator {
    private typealias Fixture = TimelineBenchFixture

    let postDigest: String

    private var random = SeededRandom()
    private var minute = 0
    private var sender = TimelineBenchFixture.helena
    private var rowNumber = 0
    private var day = 0
    private var previousBody = Corpus.short[0]

    init(postDigest: String) {
        self.postDigest = postDigest
    }

    mutating func chat() -> [TimelineBenchRow] {
        var rows = [TimelineBenchRow(item: TimelineStartRoomTimelineItem(name: "Weekend trip"), kind: "timelineStart")]
        let totalWeight = Kind.weights.reduce(0) { $0 + $1.weight }
        let markerRow = TimelineBenchFixture.maximumRowCount - 28

        while rows.count < TimelineBenchFixture.maximumRowCount {
            if rows.count % 46 == 1 {
                rows.append(separator())
            }
            if rows.count == markerRow {
                rows.append(TimelineBenchRow(item: ReadMarkerRoomTimelineItem(id: .virtual(uniqueID: .init("read-marker"))), kind: "readMarker"))
            }

            advance()
            var pick = random.next(below: totalWeight)
            let kind = Kind.weights.first { entry in
                pick -= entry.weight
                return pick < 0
            }?.kind ?? .textShort
            rows.append(TimelineBenchRow(item: makeItem(kind), kind: kind.rawValue))
        }
        return addingReadReceipts(to: rows)
    }
    
    /// Each person's receipt sits on the newest message they've read, a little way up from the end.
    private func addingReadReceipts(to rows: [TimelineBenchRow]) -> [TimelineBenchRow] {
        var rows = rows
        for (offset, person) in Fixture.people.enumerated() {
            guard let index = rows[..<(rows.count - 3 - offset * 6)].lastIndex(where: { $0.item is TextRoomTimelineItem }),
                  var item = rows[index].item as? TextRoomTimelineItem else {
                continue
            }
            item.properties.orderedReadReceipts.append(ReadReceipt(userID: person.id, formattedTimestamp: nil))
            rows[index] = TimelineBenchRow(item: item, kind: rows[index].kind)
        }
        return rows
    }

    /// A person writes a few messages in a row, a minute or two apart, which is what groups rows.
    private mutating func advance() {
        rowNumber += 1
        minute += random.chance(8) ? 40 + random.next(below: 120) : random.next(below: 3)
        guard random.chance(35) else { return }
        let everyone = Fixture.people + [Fixture.me, Fixture.me]
        sender = everyone[random.next(below: everyone.count)]
    }

    private mutating func separator() -> TimelineBenchRow {
        day += 1
        minute += 24 * 60
        return TimelineBenchRow(item: SeparatorRoomTimelineItem(id: .virtual(uniqueID: .init("day-\(day)")), timestamp: Fixture.date(minute: minute)), kind: "separator")
    }

    private var id: TimelineItemIdentifier {
        Fixture.event("row-\(rowNumber)")
    }

    private var date: Date {
        Fixture.date(minute: minute)
    }

    private var isOutgoing: Bool {
        sender.id == Fixture.me.id
    }

    private mutating func makeItem(_ kind: Kind) -> RoomTimelineItemProtocol {
        switch kind {
        case .textShort: text(pick(Corpus.short))
        case .textLong: text(pick(Corpus.long))
        case .textFormatted: formatted(pick(Corpus.html))
        case .textEmoji: emoji()
        case .reply: reply()
        case .reactions: text(pick(Corpus.short), properties: .init(reactions: reactions()))
        case .thread: thread()
        case .image: image(caption: nil)
        case .imageCaption: image(caption: pick(Corpus.short))
        case .gallery: gallery()
        case .video: video()
        case .file: file()
        case .audio: audio()
        case .voice: voice()
        case .call: call()
        case .notice: notice()
        case .draft: draft()
        case .generating: generating()
        case .state: state("\(sender.displayName ?? "Someone") changed the room name")
        case .group: group()
        case .poll: poll()
        case .emote: emote()
        case .noticeMessage: noticeMessage()
        case .redacted: redacted()
        case .encrypted: encrypted()
        case .sticker: sticker()
        case .post: post()
        }
    }

    private mutating func pick(_ corpus: [String]) -> String {
        let body = corpus[random.next(below: corpus.count)]
        previousBody = body
        return body
    }

    private func text(_ body: String, properties: RoomTimelineItemProperties = .init()) -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: isOutgoing, canBeRepliedTo: true,
                             sender: sender, content: .init(body: body), properties: properties)
    }

    private func formatted(_ html: String) -> TextRoomTimelineItem {
        let attributedString = AttributedStringBuilder(mentionBuilder: MentionBuilder()).fromHTML(html)
        return TextRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: isOutgoing, canBeRepliedTo: true,
                                    sender: sender, content: .init(body: "", formattedBody: attributedString, formattedBodyHTMLString: html))
    }

    private mutating func emoji() -> TextRoomTimelineItem {
        TextRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: isOutgoing, canBeRepliedTo: true, shouldBoost: true,
                             sender: sender, content: .init(body: pick(Corpus.emoji)))
    }

    private mutating func reply() -> TextRoomTimelineItem {
        let quoted = previousBody
        let quotedSender = Fixture.people[random.next(below: Fixture.people.count)]
        return text(pick(Corpus.short),
                    properties: .init(replyDetails: .loaded(sender: quotedSender, eventID: "$quoted-\(rowNumber)",
                                                            eventContent: .message(.text(.init(body: quoted))))))
    }

    private mutating func reactions() -> [AggregatedReaction] {
        let keys = ["👍", "❤️", "😂", "🎉", "🔥", "🙏"]
        let start = random.next(below: keys.count)
        return (0...random.next(below: 3)).map { offset in
            let senders = Fixture.people.prefix(1 + random.next(below: 4)).map { ReactionSender(id: $0.id, timestamp: date) }
            return AggregatedReaction(accountOwnerID: Fixture.me.id, key: keys[(start + offset) % keys.count], senders: senders)
        }
    }

    private mutating func thread() -> TextRoomTimelineItem {
        let replier = Fixture.people[random.next(below: Fixture.people.count)]
        return text(pick(Corpus.short),
                    properties: .init(threadSummary: .loaded(senderID: replier.id, sender: replier,
                                                             latestEventContent: .message(.text(.init(body: pick(Corpus.short)))),
                                                             numberOfReplies: 1 + random.next(below: 9))))
    }

    private func mediaSource(_ name: String, mimeType: String) -> MediaSourceProxy {
        guard let url = URL(string: "mxc://spiral.md/\(name)"),
              let source = try? MediaSourceProxy(url: url, mimeType: mimeType) else {
            fatalError("Invalid media source")
        }
        return source
    }

    /// Each picture has an address of its own, so a scroll pays for each one as it would in a real chat.
    private mutating func imageContent(_ name: String, caption: String?) -> ImageRoomTimelineItemContent {
        let shapes: [(width: UInt64, height: UInt64)] = [(2730, 2048), (2048, 2730), (2560, 1440), (2048, 2048)]
        let shape = shapes[random.next(below: shapes.count)]
        let thumbnailHeight = 800 * shape.height / shape.width
        return ImageRoomTimelineItemContent(filename: "\(name).jpg",
                                            caption: caption,
                                            imageInfo: ImageInfoProxy(source: mediaSource(name, mimeType: "image/jpeg"), width: shape.width, height: shape.height,
                                                                      mimeType: "image/jpeg", fileSize: 717_000),
                                            thumbnailInfo: ImageInfoProxy(source: mediaSource("\(name)-thumbnail", mimeType: "image/jpeg"), width: 800, height: thumbnailHeight,
                                                                          mimeType: "image/jpeg", fileSize: 84000),
                                            blurhash: "L%KUc%kqS$RP?Ks,WEf8OlrqaekW",
                                            contentType: .jpeg)
    }

    private mutating func image(caption: String?) -> ImageRoomTimelineItem {
        ImageRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true,
                              sender: sender, content: imageContent("image-\(rowNumber)", caption: caption))
    }

    private mutating func gallery() -> GalleryRoomTimelineItem {
        let items: [GalleryItem] = (0..<(2 + random.next(below: 3))).map { index in
            .image(id: GalleryItemID(timelineItemID: id, mediaIndex: index), imageContent("gallery-\(rowNumber)-\(index)", caption: nil))
        }
        return GalleryRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true,
                                       sender: sender, content: .init(body: "Gallery (\(items.count) items)", caption: pick(Corpus.short), items: items))
    }

    private func video() -> VideoRoomTimelineItem {
        VideoRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender,
                              content: .init(filename: "video-\(rowNumber).mp4",
                                             videoInfo: VideoInfoProxy(source: mediaSource("video-\(rowNumber)", mimeType: "video/mp4").underlyingSource,
                                                                       duration: 42, width: 1920, height: 1080, mimeType: "video/mp4", fileSize: 12_000_000),
                                             thumbnailInfo: ImageInfoProxy(source: mediaSource("video-\(rowNumber)-thumbnail", mimeType: "image/jpeg"), width: 800, height: 450,
                                                                           mimeType: "image/jpeg", fileSize: 98000),
                                             blurhash: "KtI~70X5V?yss9oyrYs:t6"))
    }

    private mutating func file() -> FileRoomTimelineItem {
        FileRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender,
                             content: .init(filename: "receipts-\(rowNumber).pdf",
                                            caption: random.chance(30) ? pick(Corpus.short) : nil,
                                            source: mediaSource("file-\(rowNumber)", mimeType: "application/pdf"),
                                            fileSize: 2_400_000,
                                            thumbnailSource: nil,
                                            contentType: .pdf))
    }

    private func audio() -> AudioRoomTimelineItem {
        AudioRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender,
                              content: .init(filename: "song-\(rowNumber).mp3", duration: 100, waveform: nil,
                                             source: mediaSource("audio-\(rowNumber)", mimeType: "audio/mpeg"), fileSize: nil, contentType: .mp3))
    }

    private func voice() -> VoiceMessageRoomTimelineItem {
        VoiceMessageRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender,
                                     content: .init(filename: "voice-\(rowNumber).ogg", duration: 18, waveform: EstimatedWaveform.mockWaveform,
                                                    source: mediaSource("voice-\(rowNumber)", mimeType: "audio/ogg"), fileSize: nil, contentType: .audio))
    }

    private mutating func call() -> CallNotificationRoomTimelineItem {
        let outcomes: [CallNotificationRoomTimelineItem.TombstonedOutcome] = [.answered(duration: 310), .missed, .cancelled,
                                                                              .groupCall(duration: 754, ownUserJoined: true), .declined(byMe: false)]
        return CallNotificationRoomTimelineItem(id: id, timestamp: date, sender: sender, isDM: false, isVoiceCall: random.chance(70),
                                                callState: .tombstoned(outcome: outcomes[random.next(below: outcomes.count)]), isOutgoing: isOutgoing)
    }

    private mutating func notice() -> RoomTimelineItemProtocol {
        let facts = [#"{"kind":"welcome","owner_display_name":"Helena","agent_display_name":"Helena's Assistant","behavior":"personal_assistant"}"#,
                     #"{"kind":"reply_failed"}"#,
                     #"{"kind":"message_passed_to_owner","owner_display_name":"Helena"}"#,
                     #"{"kind":"ai_consent_needed","agent_display_name":"Helena's Assistant"}"#]
        let data = #"{"com.spiral.notice":\#(facts[random.next(below: facts.count)])}"#
        guard let notice = SpiralNotice(msgtype: SpiralNotice.msgtype, data: data) else {
            fatalError("Invalid notice")
        }
        return SpiralNoticeRoomTimelineItem(id: id, timestamp: date, sender: Fixture.assistant, notice: notice)
    }

    /// Its digest fails on purpose, as in the previews: a sound draft starts a web view for each row.
    private func draft() -> InteractiveDraftRoomTimelineItem {
        InteractiveDraftRoomTimelineItem(id: id, body: "Where do we eat?", timestamp: date, isOutgoing: false, isEditable: false, canBeRepliedTo: false,
                                         sender: Fixture.assistant,
                                         draft: SpiralAppDraft(InteractiveDraftContent(body: "Where do we eat?", title: "Where do we eat?", aspect: "16:9", manifestJson: "{}",
                                                                                       source: "", sha256: String(repeating: "0", count: 64), version: 1,
                                                                                       generatedByAgentId: nil, targetRoomId: nil)))
    }

    private func generating() -> InteractiveGeneratingRoomTimelineItem {
        InteractiveGeneratingRoomTimelineItem(id: id, body: "Creating draft v1…", timestamp: date, isOutgoing: false, isEditable: false, canBeRepliedTo: false,
                                              sender: Fixture.assistant)
    }

    private func state(_ body: String, suffix: String = "") -> StateRoomTimelineItem {
        StateRoomTimelineItem(id: Fixture.event("row-\(rowNumber)\(suffix)"), body: body, timestamp: date, isOutgoing: isOutgoing, isEditable: false,
                              canBeRepliedTo: false, sender: sender)
    }

    private func group() -> CollapsibleTimelineItem {
        CollapsibleTimelineItem(items: [state("Marcus Lee joined the room", suffix: "-a"), state("Helena Ortiz changed the topic", suffix: "-b"),
                                        state("Jacob Weiss left the room", suffix: "-c")])
    }

    private func poll() -> PollRoomTimelineItem {
        PollRoomTimelineItem(id: id, poll: .mock(question: "Where do we eat on Saturday?",
                                                 options: [.mock(text: "The pier", votes: 2, allVotes: 5), .mock(text: "Back at the cabin", votes: 3, allVotes: 5, isWinning: true)],
                                                 votes: [:],
                                                 createdByAccountOwner: isOutgoing),
                             body: "poll", timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender, properties: .init())
    }

    private func emote() -> EmoteRoomTimelineItem {
        EmoteRoomTimelineItem(id: id, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender,
                              content: .init(body: "waves from the jetty"))
    }

    private mutating func noticeMessage() -> NoticeRoomTimelineItem {
        NoticeRoomTimelineItem(id: id, timestamp: date, isOutgoing: false, isEditable: false, canBeRepliedTo: true, sender: Fixture.assistant,
                               content: .init(body: pick(Corpus.short)))
    }

    private func redacted() -> RedactedRoomTimelineItem {
        RedactedRoomTimelineItem(id: id, body: L10n.commonMessageRemoved, timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: false, sender: sender)
    }

    private func encrypted() -> EncryptedRoomTimelineItem {
        EncryptedRoomTimelineItem(id: id, body: L10n.commonWaitingForDecryptionKey, encryptionType: .megolmV1AesSha2(sessionID: "session", cause: .unknown),
                                  timestamp: date, isOutgoing: false, isEditable: false, canBeRepliedTo: false, sender: sender)
    }

    private func sticker() -> StickerRoomTimelineItem {
        StickerRoomTimelineItem(id: id, body: "A thumbs up", timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender,
                                imageInfo: ImageInfoProxy(source: mediaSource("sticker-\(rowNumber)", mimeType: "image/jpeg"), width: 512, height: 512,
                                                          mimeType: "image/jpeg", fileSize: 40000),
                                blurhash: "L%KUc%kqS$RP?Ks,WEf8OlrqaekW")
    }

    private mutating func post() -> InteractivePostRoomTimelineItem {
        let aspects = ["1:1", "4:3", "16:9"]
        return InteractivePostRoomTimelineItem(id: id, body: "Where do we eat?", timestamp: date, isOutgoing: isOutgoing, isEditable: false, canBeRepliedTo: true, sender: sender,
                                               post: SpiralAppPost(InteractivePostContent(body: "Where do we eat?", appId: "wheel", runtime: "1", title: "Where do we eat?",
                                                                                          aspect: aspects[random.next(below: aspects.count)], stateChannel: "matrix",
                                                                                          sha256: postDigest, url: "mxc://spiral.md/post-artifact", fileJson: nil)))
    }
}

// MARK: - Words

private enum Corpus {
    static let short = ["Who's bringing the map on Saturday?", "I've got it", "And the cabin booking came through", "Is parking included?",
                        "Yes, two spaces by the gate", "Perfect, thank you!", "Leaving at eight, so we get there before the rain", "Is there a lake?",
                        "Two minutes' walk, kayaks included", "And the key is under the blue pot", "Where do we meet?", "These are lovely", "Same time next year?",
                        "Booking it now", "On my way", "Ok", "Yes", "Haha 😂", "Sounds good 👍", "Can you call me later?", "Running ten minutes late, sorry",
                        "Did you see the forecast?", "Rain until noon, then sun", "I'll bring the snacks 🥨", "Count me in 🙋‍♂️", "See you at the station",
                        "Привіт! Як справи?", "Дякую, все добре", "Буду о восьмій", "Де зустрічаємось?", "Купи, будь ласка, хліб і оливки", "Вже їду 🚗",
                        "Can we go somewhere with a garden this time?", "Last year's room had no windows", "Morning all!", "We need a headcount by tonight"]

    static let long = ["See you on Friday at ten, by the main gate. It's a long walk from the station, so give yourself time, and bring a coat: "
        + "the last bus back leaves at six and the wind off the lake is cold by then.",
        "So here's the plan for the weekend. We leave at eight, stop for coffee at the place by the bridge, get to the cabin around noon, and whoever "
            + "arrives first turns the heating on. The key is under the blue pot. There's no phone signal past the second gate, so if anything changes send it before you set off.",
        "I went through the receipts last night and I think we've paid twice for the boat. The first charge is from the booking in June, the second one "
            + "came through on Tuesday with a slightly different reference. Could you check whether your card shows the same thing? If it does I'll write to them today and ask for one of them back.",
        "Отже, план такий: виїжджаємо о восьмій, по дорозі заїдемо по каву, а до обіду вже будемо на місці. Ключ під синім вазоном. "
            + "Зв'язку за другими воротами майже немає, тому якщо щось зміниться, напишіть заздалегідь, бо потім ми просто нічого не побачимо до вечора.",
        "Short version: the landlord says the heating is fixed, the plumber says it isn't, and the only thing they agree on is that it's not their fault. "
            + "I've asked for the invoice and I'll call again on Monday morning. Until then the small heater in the hall is the only thing that works, so bring a jumper."]
    
    static let html = [#"<p>This fixes it:</p><pre><code>let total = items.map(\.price).reduce(0, +)</code></pre>"#,
                       "Run <code>just ci</code> before you merge",
                       "<blockquote>The best time to plant a tree was twenty years ago.</blockquote><p>The second best is now</p>",
                       "<ul><li>Bread</li><li>Olives</li><li>Two lemons</li></ul>",
                       #"<a href="https://matrix.to/#/@helena:spiral.md">@helena:spiral.md</a> could you check this?"#,
                       #"Tickets are on <a href="https://spiral.md/tickets">spiral.md/tickets</a>"#,
                       "That is <b>not</b> what she <i>said</i>"]

    static let emoji = ["🎉😂", "👍", "❤️❤️", "🚣‍♂️", "🥗🌮"]
}

#endif
