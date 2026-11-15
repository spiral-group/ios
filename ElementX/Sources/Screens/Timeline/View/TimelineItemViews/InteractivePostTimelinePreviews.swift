//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, posts-in-chat): an Interactive Post among a room's bubbles, so the gates and the snapshots
// reach it as the chat draws it. A running app is a web view, which no snapshot can start, so `WheelStandIn` paints edge
// to edge in its place, as a platform view, and the row around it is the real one.
//

import Compound
import MatrixRustSDK
import SwiftUI

struct InteractivePostTimeline_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static let directViewModel = makeViewModel(isDirect: true)
    static let groupViewModel = makeViewModel(isDirect: false)
    static let threadViewModel = makeViewModel(isDirect: false, timelineKind: .thread(rootEventID: "$wheel"))
    
    static var previews: some View {
        rows(directViewModel) {
            bubble("lunch", "Where do we eat?", from: helena, style: .first)
            runningPost("wheel", from: helena, style: .last)
            bubble("spin", "Spinning it now", from: me, style: .first)
            runningPost("own-wheel", aspect: "4:3", from: me, style: .last)
        }
        .previewDisplayName("Direct message")
        
        rows(groupViewModel) {
            bubble("lunch", "Where do we eat?", from: helena, style: .first)
            runningPost("wheel", from: helena, style: .middle)
            bubble("spin", "Give it a spin!", from: helena, style: .last)
            runningPost("own-wheel", aspect: "4:3", from: me, style: .single,
                        properties: .init(orderedReadReceipts: [helena, jacob].map { ReadReceipt(userID: $0.id, formattedTimestamp: nil) }))
        }
        .previewDisplayName("Group")
        
        rows(groupViewModel) {
            runningPost("wheel", aspect: "4:3", from: helena, style: .single,
                        properties: .init(threadSummary: .loaded(senderID: jacob.id,
                                                                 sender: jacob,
                                                                 latestEventContent: .message(.text(.init(body: "Pizza again?"))),
                                                                 numberOfReplies: 3),
                                          reactions: reactions))
            runningPost("own-wheel", aspect: "16:9", from: me, style: .single, properties: .init(reactions: reactions))
        }
        .previewDisplayName("Reactions and a thread")
        
        rows(groupViewModel) {
            runningPost("wheel", aspect: "16:9", from: me, style: .single,
                        properties: .init(replyDetails: .loaded(sender: helena,
                                                                eventID: "$lunch",
                                                                eventContent: .message(.text(.init(body: "Where do we eat?"))))))
            runningPost("own-wheel", aspect: "16:9", from: me, style: .single,
                        properties: .init(deliveryStatus: .sendingFailed(.unknown(reason: nil))))
            runningPost("warned", aspect: "16:9", from: helena, style: .single,
                        properties: .init(encryptionAuthenticity: .unsignedDevice(color: .red)))
        }
        .previewDisplayName("A reply and a failed send")
        
        rows(groupViewModel) {
            quietPost("waiting", from: helena)
            quietPost("own-waiting", from: me)
            quietPost("newer", runtime: "2", from: helena)
            quietPost("own-newer", runtime: "2", from: me)
        }
        .previewDisplayName("Before it runs")
        
        rows(threadViewModel) {
            runningPost("wheel", aspect: "4:3", from: helena, style: .single, properties: .init(isThreaded: true))
            bubble("pizza", "Pizza again?", from: jacob, style: .single)
            runningPost("own-wheel", aspect: "4:3", from: me, style: .single, properties: .init(isThreaded: true))
        }
        .previewDisplayName("In a thread")
        
        rows(threadViewModel) {
            InteractiveDraftRoomTimelineView(timelineItem: draft)
            InteractiveGeneratingRoomTimelineView(timelineItem: generating)
        }
        .previewDisplayName("A draft and a generating card")
    }
    
    private static func rows(_ viewModel: TimelineViewModel, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.vertical, 8)
        .background(Color.compound.bgCanvasDefault)
        .environmentObject(viewModel.context)
        .environment(\.timelineContext, viewModel.context)
    }
    
    private static func bubble(_ id: String, _ body: String, from sender: TimelineItemSender, style: TimelineGroupStyle) -> some View {
        let item = TextRoomTimelineItem(id: event(id),
                                        timestamp: .mock,
                                        isOutgoing: sender.id == me.id,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: sender,
                                        content: .init(body: body))
        return RoomTimelineItemView(viewState: .init(item: item, groupStyle: style))
    }
    
    /// The row as it is once the app has drawn.
    private static func runningPost(_ id: String,
                                    aspect: String = "1:1",
                                    from sender: TimelineItemSender,
                                    style: TimelineGroupStyle,
                                    properties: RoomTimelineItemProperties = .init()) -> some View {
        let item = post(id, aspect: aspect, runtime: "1", from: sender, properties: properties)
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
        .environment(\.timelineGroupStyle, style)
    }
    
    /// The real row, which shows its card until an app has started.
    private static func quietPost(_ id: String, runtime: String = "1", from sender: TimelineItemSender) -> some View {
        InteractivePostRoomTimelineView(timelineItem: post(id, aspect: "16:9", runtime: runtime, from: sender), slot: SpiralAppSlot())
    }
    
    private static func post(_ id: String,
                             aspect: String,
                             runtime: String,
                             from sender: TimelineItemSender,
                             properties: RoomTimelineItemProperties = .init()) -> InteractivePostRoomTimelineItem {
        InteractivePostRoomTimelineItem(id: event(id),
                                        body: "Where do we eat?",
                                        timestamp: .mock,
                                        isOutgoing: sender.id == me.id,
                                        isEditable: false,
                                        canBeRepliedTo: true,
                                        sender: sender,
                                        post: SpiralAppPost(InteractivePostContent(body: "Where do we eat?",
                                                                                   appId: "wheel",
                                                                                   runtime: runtime,
                                                                                   title: "Where do we eat?",
                                                                                   aspect: aspect,
                                                                                   stateChannel: "matrix",
                                                                                   sha256: String(repeating: "a", count: 64),
                                                                                   url: "mxc://spiral.md/wheel",
                                                                                   fileJson: nil)),
                                        properties: properties)
    }
    
    private static var draft: InteractiveDraftRoomTimelineItem {
        InteractiveDraftRoomTimelineItem(id: event("draft"),
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
    
    /// Dated at `.mock`, so its card is the stale one and no band moves in a snapshot.
    private static var generating: InteractiveGeneratingRoomTimelineItem {
        InteractiveGeneratingRoomTimelineItem(id: event("generating"),
                                              body: "Creating draft v1…",
                                              timestamp: .mock,
                                              isOutgoing: false,
                                              isEditable: false,
                                              canBeRepliedTo: false,
                                              sender: helena)
    }
    
    private static func makeViewModel(isDirect: Bool, timelineKind: TimelineKind = .live) -> TimelineViewModel {
        let roomProxy = JoinedRoomProxyMock(.init(name: "Lunch",
                                                  isDirect: isDirect,
                                                  hasOngoingCall: false,
                                                  members: isDirect ? [.mockMe, .mockAlice] : [.mockMe, .mockAlice, .mockBob, .mockCharlie]))
        let userSettings = UserSettings.mock()
        userSettings.app.threadsEnabled = true
        return TimelineViewModel(roomProxy: roomProxy,
                                 timelineController: TimelineControllerMock(.init(timelineKind: timelineKind)),
                                 userSession: UserSessionMock(.init(userSettings: userSettings)),
                                 mediaPlayerProvider: MediaPlayerProviderMock(),
                                 userIndicatorController: UserIndicatorControllerMock(),
                                 appMediator: AppMediatorMock(.init()),
                                 analyticsService: AnalyticsServiceMock(.init()),
                                 emojiProvider: EmojiProvider(userSettings: userSettings),
                                 linkMetadataProvider: LinkMetadataProvider(),
                                 timelineControllerFactory: TimelineControllerFactoryMock(.init()))
    }
    
    private static func event(_ id: String) -> TimelineItemIdentifier {
        .event(uniqueID: .init(id), eventOrTransactionID: .eventID("$\(id)"))
    }
    
    private static let helena = TimelineItemSender(id: "@helena:spiral.md", displayName: "Helena Ortiz")
    private static let jacob = TimelineItemSender(id: "@jacob:spiral.md", displayName: "Jacob")
    private static let me = TimelineItemSender(id: RoomMemberProxyMock.mockMe.userID, displayName: "Me")
    
    private static var reactions: [AggregatedReaction] {
        [AggregatedReaction(accountOwnerID: me.id, key: "🍕", senders: [me, jacob].map { ReactionSender(id: $0.id, timestamp: .mock) }),
         AggregatedReaction(accountOwnerID: me.id, key: "🎉", senders: [ReactionSender(id: helena.id, timestamp: .mock)])]
    }
}

/// Stands in for a post's web view: a platform view that paints to its edges, as an app's page does.
struct WheelStandIn: UIViewRepresentable {
    func makeUIView(context: Context) -> WheelStandInView {
        WheelStandInView()
    }
    
    func updateUIView(_ uiView: WheelStandInView, context: Context) { }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: WheelStandInView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class WheelStandInView: UIView {
    private let segments: [Color] = [.compound.iconAccentPrimary, .compound.bgCriticalPrimary, .compound.iconSuccessPrimary, .compound.iconSecondary]
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Color.compound.bgActionPrimaryRest)
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.4
        let count = segments.count * 2
        for index in 0..<count {
            let path = UIBezierPath()
            path.move(to: centre)
            path.addArc(withCenter: centre,
                        radius: radius,
                        startAngle: CGFloat(index) / CGFloat(count) * 2 * .pi,
                        endAngle: CGFloat(index + 1) / CGFloat(count) * 2 * .pi,
                        clockwise: true)
            path.close()
            UIColor(segments[index % segments.count]).setFill()
            path.fill()
        }
    }
}
