//
import OrderedCollections

// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
import SwiftUI

struct RoomTimelineItemView: View {
    @Environment(\.timelineContext) var context
    @Environment(\.timelineRowMotion) private var rowMotion // AGENT-PLATFORM (Brief 0083, question 359)
    @ObservedObject var viewState: RoomTimelineItemViewState
    
    var body: some View {
        #if SPIRAL_TIMELINE_BENCH // AGENT-PLATFORM (Brief 0083, question 359): how many rows re-render.
        let _ = TimelineBenchProbe.shared.noteRowBody(viewState.id)
        #endif
        #if DEBUG
        let _ = TimelineSignposts.noteBody(.row, of: viewState.id) // AGENT-PLATFORM (Brief 0083, question 359)
        #endif
        timelineView
            .animation(rowMotion.animation, value: viewState.groupStyle)
            .animation(rowMotion.animation, value: viewState.type)
            .environment(\.timelineGroupStyle, viewState.groupStyle)
            .environment(\.timelineRowContext, viewState.rowContext) // AGENT-PLATFORM (Brief 0083, question 359)
            .onAppear {
                context?.send(viewAction: .itemAppeared(itemID: viewState.identifier))
            }
            .onDisappear {
                context?.send(viewAction: .itemDisappeared(itemID: viewState.identifier))
            }
    }
    
    @ViewBuilder private var timelineView: some View {
        switch viewState.type {
        case .text(let item):
            TextRoomTimelineView(timelineItem: item, linkMetadata: linkMetadataForItem(item))
        case .separator(let item):
            SeparatorRoomTimelineView(timelineItem: item)
        case .image(let item):
            ImageRoomTimelineView(timelineItem: item)
        case .video(let item):
            VideoRoomTimelineView(timelineItem: item)
        case .audio(let item):
            AudioRoomTimelineView(timelineItem: item)
        case .file(let item):
            FileRoomTimelineView(timelineItem: item)
        case .gallery(let item):
            GalleryRoomTimelineView(timelineItem: item)
        case .emote(let item):
            EmoteRoomTimelineView(timelineItem: item)
        case .notice(let item):
            NoticeRoomTimelineView(timelineItem: item)
        case .redacted(let item):
            RedactedRoomTimelineView(timelineItem: item)
        case .encrypted(let item):
            EncryptedRoomTimelineView(timelineItem: item)
        case .readMarker:
            ReadMarkerRoomTimelineView()
        case .paginationIndicator:
            PaginationIndicatorRoomTimelineView()
        case .sticker(let item):
            StickerRoomTimelineView(timelineItem: item)
        // AGENT-PLATFORM (Brief 0066)
        case .interactivePost(let item):
            // The slot is the row's only way to learn that an app has started;
            // the registry decides that long after this.
            //
            // A post with no event id yet — a local echo, still on its way to
            // the server — gets a slot of its own that the registry never sees.
            // It cannot run: its state lives under the event id it does not
            // have. Keying those on `""` put every unsent post in the world in
            // one bucket, and filled the registry with entries nothing would
            // ever arm.
            let slot = item.id.eventID.flatMap {
                context?.viewState.spiralAppHosts?.slot(for: $0, post: item.post)
            } ?? SpiralAppSlot()
            #if SPIRAL_TIMELINE_BENCH // AGENT-PLATFORM (Brief 0083, question 359): when the post has drawn.
            let _ = TimelineBenchProbe.shared.notePost(item.id.uniqueID, slot: slot)
            #endif
            InteractivePostRoomTimelineView(timelineItem: item, slot: slot)
        case .interactiveDraft(let item):
            InteractiveDraftRoomTimelineView(timelineItem: item)
        case .interactiveGenerating(let item):
            InteractiveGeneratingRoomTimelineView(timelineItem: item)
        case .spiralNotice(let item):
            SpiralNoticeRoomTimelineView(timelineItem: item)
        case .callSummary(let item):
            CallSummaryRoomTimelineView(timelineItem: item)
        case .unsupported(let item):
            UnsupportedRoomTimelineView(timelineItem: item)
        case .timelineStart(let item):
            TimelineStartRoomTimelineView(timelineItem: item)
        case .state(let item):
            StateRoomTimelineView(timelineItem: item)
        case .group(let item):
            CollapsibleRoomTimelineView(timelineItem: item)
        case .location(let item):
            LocationRoomTimelineView(timelineItem: item)
        case .poll(let item):
            PollRoomTimelineView(timelineItem: item)
        case .voice(let item):
            let playerState = context?.viewState.audioPlayerStateProvider?(item.id) ?? AudioPlayerState(id: .timelineItemIdentifier(item.id),
                                                                                                        title: L10n.commonVoiceMessage,
                                                                                                        duration: 0)
            VoiceMessageRoomTimelineView(timelineItem: item, playerState: playerState)
        case .callInvite:
            CallInviteRoomTimelineView()
        case .callNotification(let item):
            CallNotificationRoomTimelineView(timelineItem: item)
        case .liveLocation(let item):
            LiveLocationRoomTimelineView(timelineItem: item, isStopped: viewState.rowContext.isLiveLocationStopped)
        }
    }
    
    private func linkMetadataForItem(_ item: TextRoomTimelineItem) -> OrderedDictionary<URL, LinkMetadataProviderItem> {
        var linkMetadata = OrderedDictionary<URL, LinkMetadataProviderItem>()
        for url in item.links.prefix(TextRoomTimelineView.maxLinkPreviewsToRender) {
            if let item = context?.viewState.linkMetadataProvider?.metadataItems[url] {
                linkMetadata[url] = item
            } else {
                linkMetadata[url] = LinkMetadataProviderItem(metadata: nil)
            }
        }
        return linkMetadata
    }
}
