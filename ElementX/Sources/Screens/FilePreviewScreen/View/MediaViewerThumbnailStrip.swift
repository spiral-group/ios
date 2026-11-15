//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413): the chat's media as thumbnails under the viewer, as in iOS Photos —
// the current one wider and outlined, a tap jumps to another.
//

import Compound
import SpiralTokens
import SwiftUI

struct MediaViewerThumbnailStrip: View {
    @ObservedObject var context: TimelineMediaPreviewViewModel.Context

    private static let height: CGFloat = 44
    private static let width: CGFloat = 30
    private static let currentWidth: CGFloat = 52

    private var dataSource: TimelineMediaPreviewDataSource {
        context.viewState.dataSource
    }

    private var currentID: MediaPreviewItemID? {
        context.viewState.currentItem.mediaItem?.id
    }

    @State private var width: CGFloat = 0
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(Array(dataSource.previewItems.enumerated()), id: \.element.id) { index, media in
                        thumbnail(media, number: index + 1)
                    }
                }
                .padding(.vertical, 2)
            }
            // Lets the first and last thumbnails reach the middle, where the current one always sits.
            .contentMargins(.horizontal, max(0, (width - Self.currentWidth) / 2 - 4), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
            .scrollIndicators(.hidden)
            .frame(height: Self.height + 4)
            .onAppear { scrollToCurrent(proxy, animated: false) }
            .onChange(of: currentID) { scrollToCurrent(proxy, animated: true) }
            .onChange(of: dataSource.previewItems.count) { scrollToCurrent(proxy, animated: false) }
        }
    }

    private func thumbnail(_ media: TimelineMediaPreviewItem.Media, number: Int) -> some View {
        let isCurrent = media.id == currentID

        return Button {
            context.send(viewAction: .showPage(.media(media.id)))
        } label: {
            MediaViewerThumbnail(media: media, mediaProvider: context.mediaProvider)
                .frame(width: isCurrent ? Self.currentWidth : Self.width, height: Self.height)
                .clipShape(RoundedRectangle(cornerRadius: SpiralRadius.thumbnail / 2))
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: SpiralRadius.thumbnail / 2)
                            .strokeBorder(Color.compound.iconPrimary, lineWidth: 2)
                    }
                }
                .padding(.horizontal, isCurrent ? 4 : 0)
                .animation(.easeOut(duration: 0.2), value: isCurrent)
        }
        .buttonStyle(.plain)
        .id(media.id)
        .accessibilityLabel(accessibilityLabel(for: media, number: number))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func accessibilityLabel(for media: TimelineMediaPreviewItem.Media, number: Int) -> String {
        let kind = switch media.kind {
        case .image: L10n.commonImage
        case .video: L10n.commonVideo
        case .audio: L10n.commonAudio
        case .file: L10n.commonFile
        }
        return "\(kind), \(UntranslatedL10n.screenMediaViewerPosition(number, dataSource.previewItems.count))"
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let currentID else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(currentID, anchor: .center) }
        } else {
            proxy.scrollTo(currentID, anchor: .center)
        }
    }
}

private struct MediaViewerThumbnail: View {
    let media: TimelineMediaPreviewItem.Media
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        ZStack {
            Color.compound.bgSubtlePrimary

            if let source = media.thumbnailMediaSource ?? (media.kind == .image ? media.mediaSource : nil) {
                LoadableImage(mediaSource: source,
                              blurhash: media.blurhash,
                              size: CGSize(width: 120, height: 120),
                              mediaProvider: mediaProvider) {
                    Color.clear
                }
                .aspectRatio(contentMode: .fill)
            } else {
                CompoundIcon(media.kind == .audio ? \.audio : \.document, size: .small, relativeTo: .compound.bodySM)
                    .foregroundStyle(.compound.iconSecondary)
            }

            if media.kind == .video {
                CompoundIcon(\.playSolid, size: .custom(10), relativeTo: .compound.bodyXS)
                    .foregroundStyle(.compound.iconOnSolidPrimary)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(3)
            }
        }
        .accessibilityHidden(true)
    }
}
