//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

enum TimelineReplyViewPlacement {
    case timeline
    case composer
}

struct TimelineReplyView: View {
    @Environment(\.timelineContext) private var timelineContext
    @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083)
    
    let placement: TimelineReplyViewPlacement // AGENT-PLATFORM (Brief 0083): read, so no periphery:ignore
    let timelineItemReplyDetails: TimelineItemReplyDetails?
    var maxWidth: CGFloat?
    
    var body: some View {
        ContentScanningView(contentScannerService: timelineContext?.contentScannerService,
                            mediaSource: scannedMediaSource,
                            thumbnailSource: scannedThumbnailSource,
                            containerShowsFailure: false) {
            content
                .roundedContainer(padding: 4,
                                  maxWidth: maxWidth,
                                  backgroundColor: quoteBackgroundColor,
                                  borderColor: nil,
                                  isBare: placement == .composer) // AGENT-PLATFORM (Brief 0083): the composer draws the block
        } scanningContent: {
            LoadingReplyView()
                .roundedContainer(padding: 4,
                                  maxWidth: maxWidth,
                                  backgroundColor: quoteBackgroundColor,
                                  borderColor: nil,
                                  isBare: placement == .composer) // AGENT-PLATFORM (Brief 0083): the composer draws the block
        } unsafeContent: { failure in
            ContentScanningFailureView(failure: failure, isCompact: true)
                .roundedContainer(padding: 8,
                                  maxWidth: maxWidth,
                                  backgroundColor: .compound.bgCriticalSubtle,
                                  borderColor: .compound.borderCriticalSubtle)
        }
        .environment(\.isReplyInBubble, placement == .timeline) // AGENT-PLATFORM (Brief 0083)
    }
    
    // AGENT-PLATFORM (Brief 0083, the room's timeline): in a bubble the quote is a translucent block without Element's
    // outline: 6 % of the bubble's text colour on a neutral bubble, and the ink's own on an own bubble. In the composer
    // the quote is bare: `SpiralComposerHeader` draws its block.
    private var quoteBackgroundColor: Color {
        ownBubbleInk?.quoteFill ?? .compound.textPrimary.opacity(0.06)
    }
    
    /// The media source validated by the content scanner when the replied to message contains media.
    private var scannedMediaSource: MediaSourceProxy? {
        guard case .loaded(_, _, let eventContent) = timelineItemReplyDetails,
              case .message(let message) = eventContent else {
            return nil
        }
        
        switch message {
        case .audio(let content): return content.source
        case .file(let content): return content.source
        case .image(let content): return content.imageInfo.source
        case .video(let content): return content.videoInfo.source
        case .voice(let content): return content.source
        // Only the first item is scanned as it's the only one the reply previews.
        case .gallery(let content): return content.items.first?.mediaSource
        default: return nil
        }
    }
    
    /// The thumbnail source validated alongside ``scannedMediaSource`` when the replied to message has one.
    private var scannedThumbnailSource: MediaSourceProxy? {
        guard case .loaded(_, _, let eventContent) = timelineItemReplyDetails,
              case .message(let message) = eventContent else {
            return nil
        }
        
        switch message {
        case .file(let content): return content.thumbnailSource
        case .image(let content): return content.thumbnailInfo?.source
        case .video(let content): return content.thumbnailInfo?.source
        case .gallery(let content): return content.items.first?.thumbnailSource
        default: return nil
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if let timelineItemReplyDetails {
            switch timelineItemReplyDetails {
            case .loaded(let sender, _, let content):
                switch content {
                case .message(let content):
                    switch content {
                    case .audio(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: .init(kind: .icon(\.audio)))
                    case .emote(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.body,
                                  formattedBody: content.formattedBody)
                    case .file(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: .init(kind: .icon(\.attachment)))
                    case .image(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: .init(kind: .mediaSource(content.thumbnailInfo?.source ?? content.imageInfo.source)))
                    case .notice(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.body,
                                  formattedBody: content.formattedBody)
                    case .text(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.body,
                                  formattedBody: content.formattedBody)
                    case .video(let content):
                        ReplyView(sender: sender,
                                  plainBody: content.caption ?? content.filename,
                                  formattedBody: content.formattedCaption,
                                  icon: content.thumbnailInfo.map { .init(kind: .mediaSource($0.source)) })
                    case .voice:
                        ReplyView(sender: sender,
                                  plainBody: L10n.commonVoiceMessage,
                                  formattedBody: nil,
                                  icon: .init(kind: .icon(\.micOn)))
                    case .location:
                        ReplyView(sender: sender,
                                  plainBody: L10n.commonSharedLocation,
                                  formattedBody: nil,
                                  icon: .init(kind: .icon(\.locationPin)))
                    case .gallery(let content):
                        GalleryReplyView(sender: sender, content: content)
                    }
                case .poll(let question):
                    ReplyView(sender: sender,
                              plainBody: question,
                              formattedBody: nil,
                              icon: .init(kind: .icon(\.polls)))
                case .liveLocation:
                    ReplyView(sender: sender,
                              plainBody: L10n.commonSharedLiveLocation,
                              formattedBody: nil,
                              icon: .init(kind: .icon(\.locationPin)))
                // AGENT-PLATFORM (Brief 0066): a reply to an Interactive Post quotes its title.
                case .interactivePost(let title):
                    ReplyView(sender: sender,
                              plainBody: title,
                              formattedBody: nil,
                              icon: .init(kind: .icon(\.extensions)))
                case .redacted:
                    ReplyView(sender: sender,
                              plainBody: L10n.commonMessageRemoved,
                              formattedBody: nil,
                              icon: .init(kind: .icon(\.delete)))
                }
            default:
                LoadingReplyView()
            }
        }
    }
    
    /// A gallery previews its first attachment as though it had been sent on its own, counting its
    /// media when they're all images/videos and its attachments otherwise.
    private struct GalleryReplyView: View {
        let sender: TimelineItemSender
        let content: GalleryRoomTimelineItemContent
        
        private var caption: String? {
            content.caption?.isBlank == false ? content.caption : nil
        }
        
        private var isMediaGallery: Bool {
            content.items.allSatisfy { $0.isImage || $0.isVideo }
        }
        
        private var placeholder: String {
            if isMediaGallery {
                L10n.commonGalleryReplyMediaItems(content.items.count)
            } else {
                L10n.commonGalleryReplyAttachments(content.items.count)
            }
        }
        
        private var icon: ReplyView.Icon? {
            guard let item = content.items.first else { return nil }
            
            return switch item {
            case .image(_, let itemContent): .init(kind: .mediaSource(itemContent.thumbnailInfo?.source ?? itemContent.imageInfo.source))
            case .video(_, let itemContent): itemContent.thumbnailInfo.map { .init(kind: .mediaSource($0.source)) }
            case .audio: .init(kind: .icon(\.audio))
            case .file, .other: .init(kind: .icon(\.attachment))
            }
        }
        
        var body: some View {
            ReplyView(sender: sender,
                      plainBody: caption ?? placeholder,
                      formattedBody: caption == nil ? nil : content.formattedCaption,
                      icon: icon)
        }
    }
    
    private struct LoadingReplyView: View {
        var body: some View {
            ReplyView(sender: .init(id: "@alice:matrix.org"), plainBody: "Hello world", formattedBody: nil)
                .redacted(reason: .placeholder)
                .accessibilityLabel(L10n.commonLoading)
        }
    }
    
    private struct ReplyView: View {
        struct Icon {
            enum Kind {
                case mediaSource(MediaSourceProxy)
                case iconAsset(ImageAsset)
                case icon(KeyPath<CompoundIcons, Image>)
            }
            
            let kind: Kind
            let cornerRadii = 4.0
        }
        
        @Environment(\.timelineContext) private var context
        @Environment(\.isReplyInBubble) private var isReplyInBubble // AGENT-PLATFORM (Brief 0083)
        @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083)
        @ScaledMetric private var imageContainerSize = 36.0
        
        let sender: TimelineItemSender
        let plainBody: String
        let formattedBody: AttributedString?
        
        var icon: Icon?
        
        // AGENT-PLATFORM (Brief 0083, question 357): a person's colour in an incoming bubble's quote. On the blue only white reads.
        private var quotedNameForeground: BubbleForeground {
            guard isReplyInBubble, ownBubbleInk == nil else { return .primary }
            return .fixed(SenderHue(userID: sender.id).color)
        }
        
        var body: some View {
            HStack(spacing: 8) {
                iconView
                    .frame(width: imageContainerSize, height: imageContainerSize)
                    .foregroundColor(ownBubbleInk?.onStrongFill ?? .compound.iconPrimary)
                    .background(ownBubbleInk?.strongFill ?? .compound.bgSubtlePrimary)
                    .cornerRadius(icon?.cornerRadii ?? 0.0, corners: .allCorners)
                    .accessibilityHidden(true)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sender.disambiguatedDisplayName ?? sender.id)
                        .font(.compound.bodySMSemibold)
                        .bubbleForegroundStyle(quotedNameForeground) // AGENT-PLATFORM (Brief 0083): white on an own bubble
                        .accessibilityLabel(L10n.commonInReplyTo(sender.disambiguatedDisplayName ?? sender.id))
                    
                    Text(context?.viewState.buildMessagePreview(formattedBody: formattedBody, plainBody: plainBody) ?? plainBody)
                        .font(.compound.bodyMD)
                        // AGENT-PLATFORM (Brief 0083): in a bubble the bubble's text colour, since grey on the tinted
                        // block reads 4.11:1; the composer keeps the secondary grey.
                        .bubbleForegroundStyle(isReplyInBubble ? .primary : .secondary)
                        .tint(.compound.textLinkExternal)
                        .lineLimit(2)
                }
                .padding(.leading, icon == nil ? 8 : 0)
                .padding(.trailing, 8)
            }
            .accessibilityElement(children: .combine)
        }
        
        @ViewBuilder
        private var iconView: some View {
            if let icon {
                switch icon.kind {
                case .mediaSource(let mediaSource):
                    LoadableImage(mediaSource: mediaSource,
                                  size: .init(width: imageContainerSize,
                                              height: imageContainerSize),
                                  mediaProvider: context?.mediaProvider) {
                        CompoundIcon(\.image)
                            .padding(4.0)
                    }
                    .scaledToFill()
                case .iconAsset(let asset):
                    Image(asset: asset)
                        .resizable()
                        .scaledToFit()
                        .padding(8.0)
                case .icon(let keyPath):
                    CompoundIcon(keyPath, size: .medium, relativeTo: .body)
                }
            }
        }
    }
}

// AGENT-PLATFORM (Brief 0083): whether a quote is drawn inside a timeline bubble rather than over the composer.
private extension EnvironmentValues {
    @Entry var isReplyInBubble = false
}

private extension View {
    // AGENT-PLATFORM (Brief 0083): a bare quote has neither; the composer's header draws its block (`SpiralComposerHeader`).
    /// Styles the view as a rounded container with a background fill and a border.
    @ViewBuilder
    func roundedContainer(padding: CGFloat = 12,
                          maxWidth: CGFloat? = nil,
                          backgroundColor: Color,
                          borderColor: Color?, // AGENT-PLATFORM (Brief 0083): an optional border
                          isBare: Bool = false) -> some View {
        let backgroundShape = RoundedRectangle(cornerRadius: 8)
        if isBare {
            fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
        } else {
            fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .padding(padding)
                .background {
                    ZStack {
                        backgroundShape.fill(backgroundColor)
                        if let borderColor { // AGENT-PLATFORM (Brief 0083)
                            backgroundShape.stroke(borderColor)
                        }
                    }
                }
        }
    }
}

struct TimelineReplyView_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    static let scanningViewModel = TimelineViewModel.mock(contentScannerService: ContentScannerServiceMock(.init(scanResult: nil)))
    static let unsafeViewModel = TimelineViewModel.mock(contentScannerService: ContentScannerServiceMock(.init(scanResult: false)))
    
    static let attributedStringWithMention = {
        var attributedString = AttributedString("To be replaced")
        attributedString.userID = "@alice:matrix.org"
        return attributedString
    }()
    
    static let attributedStringWithAtRoomMention = {
        var attributedString = AttributedString("to be replaced")
        attributedString.allUsersMention = true
        return attributedString
    }()
    
    static let attributedStringWithRoomAliasMention = {
        var attributedString = AttributedString("to be replaced")
        attributedString.roomAlias = "#room:matrix.org"
        return attributedString
    }()
    
    static let attributedStringWithRoomIDMention = {
        var attributedString = AttributedString("to be replaced")
        attributedString.roomID = "!room:matrix.org"
        return attributedString
    }()
    
    static let attributedStringWithEventOnRoomIDMention = {
        var attributedString = AttributedString("to be replaced")
        attributedString.eventOnRoomID = .init(roomID: "!room:matrix.org", eventID: "$event")
        return attributedString
    }()
    
    static let attributedStringWithEventOnRoomAliasMention = {
        var attributedString = AttributedString("to be replaced")
        attributedString.eventOnRoomAlias = .init(alias: "#room:matrix.org", eventID: "$event")
        return attributedString
    }()
    
    static var previewItems: [TimelineReplyView] {
        [
            TimelineReplyView(placement: .timeline, timelineItemReplyDetails: .notLoaded(eventID: "")),
            
            TimelineReplyView(placement: .timeline, timelineItemReplyDetails: .loading(eventID: "")),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.text(.init(body: "This is a reply"))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.emote(.init(body: "says hello"))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .message(.notice(.init(body: "Hello world"))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.audio(.init(filename: "audio.m4a",
                                                                                                    caption: "Some audio",
                                                                                                    duration: 0,
                                                                                                    waveform: nil,
                                                                                                    source: nil,
                                                                                                    fileSize: nil,
                                                                                                    contentType: nil))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.file(.init(filename: "file.txt",
                                                                                                   caption: "Some file",
                                                                                                   source: nil,
                                                                                                   fileSize: nil,
                                                                                                   thumbnailSource: nil,
                                                                                                   contentType: nil))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.image(.init(filename: "image.jpg",
                                                                                                    caption: "Some image",
                                                                                                    imageInfo: .mockImage,
                                                                                                    thumbnailInfo: .mockThumbnail))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.video(.init(filename: "video.mp4",
                                                                                                    caption: "Some video",
                                                                                                    videoInfo: .mockVideo,
                                                                                                    thumbnailInfo: .mockVideoThumbnail))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.location(.init(body: ""))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .liveLocation)),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.voice(.init(filename: "voice-message.ogg",
                                                                                                    caption: "Some voice message",
                                                                                                    duration: 0,
                                                                                                    waveform: nil,
                                                                                                    source: nil,
                                                                                                    fileSize: nil,
                                                                                                    contentType: nil))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .message(.notice(.init(body: "", formattedBody: attributedStringWithMention))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .message(.notice(.init(body: "", formattedBody: attributedStringWithAtRoomMention))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .message(.notice(.init(body: "", formattedBody: attributedStringWithRoomAliasMention))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .message(.notice(.init(body: "", formattedBody: attributedStringWithRoomIDMention))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .message(.notice(.init(body: "", formattedBody: attributedStringWithEventOnRoomIDMention))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .message(.notice(.init(body: "", formattedBody: attributedStringWithEventOnRoomAliasMention))))),
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.gallery(.init(body: "Gallery",
                                                                                                      items: [.mockImage(index: 0),
                                                                                                              .mockVideo(index: 1)]))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                                eventID: "123",
                                                                eventContent: .message(.gallery(.init(body: "Gallery",
                                                                                                      caption: "A trip to remember 🌅",
                                                                                                      items: [.mockImage(index: 0),
                                                                                                              .mockVideo(index: 1),
                                                                                                              .mockImage(index: 2)]))))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .poll(question: "Do you like polls?"))),
            
            TimelineReplyView(placement: .timeline,
                              timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Bob"),
                                                                eventID: "123",
                                                                eventContent: .redacted))
        ]
    }
    
    static var previews: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<previewItems.count, id: \.self) { index in
                previewItems[index]
            }
        }
        .padding()
        .environment(\.timelineContext, viewModel.context)
        .previewLayout(.sizeThatFits)
        
        VStack(alignment: .leading, spacing: 20) {
            imageReply
                .environment(\.timelineContext, scanningViewModel.context)
            
            imageReply
                .environment(\.timelineContext, unsafeViewModel.context)
        }
        .padding()
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Content Scanner")
    }
    
    static var imageReply: TimelineReplyView {
        TimelineReplyView(placement: .timeline,
                          timelineItemReplyDetails: .loaded(sender: .init(id: "", displayName: "Alice"),
                                                            eventID: "123",
                                                            eventContent: .message(.image(.init(filename: "image.jpg",
                                                                                                caption: "Some image",
                                                                                                imageInfo: .mockImage,
                                                                                                thumbnailInfo: .mockThumbnail)))))
    }
}
