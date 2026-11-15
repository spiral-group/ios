//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0083, question 413, concept A): the bars of Spiral's own photo and video viewer, after
// iOS Photos. A glass ✕, a capsule with the sender, the time and «2 of 14», and ⋯ at the top; the media's caption,
// the chat's media as a strip of thumbnails and Share · Reply · Forward · Info at the bottom. They float over the
// pages in their own hosts, so a page change never lays out anything but them.
//

import Compound
import SpiralTokens
import SwiftUI

/// The bars over the top of the viewer: ✕, who sent the media and when, and ⋯.
struct MediaViewerTopBar: View {
    @ObservedObject var context: TimelineMediaPreviewViewModel.Context
    let close: () -> Void

    private var currentItem: TimelineMediaPreviewItem {
        context.viewState.currentItem
    }

    var body: some View {
        HStack(spacing: CompoundDesignTokens.space2X) {
            MediaViewerGlassButton(icon: \.close, label: L10n.actionClose, action: close)
            Spacer(minLength: 0)
            moreMenu
        }
        .overlay {
            MediaViewerTitleCapsule(item: currentItem, position: context.viewState.dataSource.position)
                .padding(.horizontal, 56)
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.top, CompoundDesignTokens.space2X)
        .padding(.bottom, CompoundDesignTokens.space2X)
    }

    @ViewBuilder
    private var moreMenu: some View {
        if let mediaItem = currentItem.mediaItem, !context.viewState.moreMenuActions.isEmpty {
            Menu {
                ForEach(context.viewState.moreMenuActions, id: \.self) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        context.send(viewAction: .menuAction(action, item: mediaItem))
                    } label: {
                        action.label
                    }
                    .disabled(action == .downloadMedia && mediaItem.fileURL == nil)
                }
            } label: {
                MediaViewerGlassGlyph(icon: \.overflowHorizontal)
            }
            .accessibilityLabel(UntranslatedL10n.a11yMediaViewerMore)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

/// What sits under the media: its caption, the chat's media as thumbnails, and Share · Reply · Forward · Info.
struct MediaViewerBottomChrome: View {
    @ObservedObject var context: TimelineMediaPreviewViewModel.Context

    private var currentItem: TimelineMediaPreviewItem {
        context.viewState.currentItem
    }

    var body: some View {
        VStack(spacing: CompoundDesignTokens.space3X) {
            if let mediaItem = currentItem.mediaItem, mediaItem.hasCaption {
                MediaViewerCaption(mediaItem: mediaItem)
            }

            if context.viewState.dataSource.previewItems.count > 1 {
                MediaViewerThumbnailStrip(context: context)
            }

            bottomBar
        }
        .padding(.top, CompoundDesignTokens.space2X)
        .padding(.bottom, CompoundDesignTokens.space2X)
    }

    private var bottomBar: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            shareButton
            Spacer(minLength: 0)
            if let mediaItem = currentItem.mediaItem {
                if context.viewState.canReplyToCurrentItem {
                    MediaViewerGlassButton(icon: \.reply, label: L10n.actionReply) {
                        context.send(viewAction: .reply(mediaItem))
                    }
                }
                if let forwardAction = context.viewState.forwardAction {
                    MediaViewerGlassButton(icon: \.forward, label: L10n.actionForward) {
                        context.send(viewAction: .menuAction(forwardAction, item: mediaItem))
                    }
                }
            }
            Spacer(minLength: 0)
            MediaViewerGlassButton(icon: \.info, label: L10n.a11yInfo) {
                if let mediaItem = currentItem.mediaItem {
                    context.send(viewAction: .showItemDetails(mediaItem))
                }
            }
            .disabled(currentItem.mediaItem == nil)
            .accessibilityIdentifier(A11yIdentifiers.mediaViewer.info)
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
    }

    @ViewBuilder
    private var shareButton: some View {
        if let fileURL = currentItem.mediaItem?.fileURL {
            ShareLink(item: fileURL) {
                MediaViewerGlassGlyph(icon: \.shareIos)
            }
            .accessibilityLabel(L10n.actionShare)
        } else {
            // Holds the place until the file has downloaded, so nothing moves when it can be shared.
            MediaViewerGlassGlyph(icon: \.shareIos)
                .opacity(0.4)
                .accessibilityLabel(L10n.actionShare)
                .accessibilityAddTraits(.isButton)
                .accessibilityRemoveTraits(.isImage)
        }
    }
}

/// The sheets and alerts the viewer shows over itself: details, deleting, saving a file, QuickLook.
struct MediaViewerSheets: View {
    @ObservedObject var context: TimelineMediaPreviewViewModel.Context

    @State private var detailsSheetHeight: CGFloat = 400

    var body: some View {
        Color.clear
            .sheet(item: $context.detailsItem) { item in
                TimelineMediaPreviewDetailsView(item: item, context: context, sheetHeight: $detailsSheetHeight)
            }
            .sheet(item: redactConfirmationItem) { item in
                TimelineMediaPreviewRedactConfirmationView(item: item, context: context)
            }
            .sheet(item: $context.exportFile) { file in
                TimelineMediaPreviewFileExportPicker(file: file)
            }
            .alert(item: $context.alertInfo)
            .interactiveQuickLook(item: $context.quickLookItem, allowEditing: false)
    }

    /// The details sheet asks to delete from inside itself, so this one only shows when ⋯ asked.
    private var redactConfirmationItem: Binding<TimelineMediaPreviewItem.Media?> {
        Binding { context.detailsItem == nil ? context.redactConfirmationItem : nil } set: { context.redactConfirmationItem = $0 }
    }
}

// MARK: - Title

/// Who sent the media, when, and where it sits among the chat's media.
private struct MediaViewerTitleCapsule: View {
    let item: TimelineMediaPreviewItem
    let position: TimelineMediaPreviewPosition?

    var body: some View {
        VStack(spacing: 0) {
            // The primary style, so the text flips with Liquid Glass as it lightens over a bright photo; the
            // secondary one is too faint on black.
            Text(title)
                .font(.compound.bodySMSemibold)
            if let subtitle {
                Text(subtitle)
                    .font(.compound.bodyXS)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .foregroundStyle(.primary)
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space1_5X)
        .frame(minHeight: 44)
        .spiralGlass(in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard let mediaItem = item.mediaItem else { return L10n.commonLoadingMore }
        return mediaItem.sender.displayName ?? mediaItem.sender.id
    }

    private var subtitle: String? {
        guard let mediaItem = item.mediaItem else { return nil }
        let date = "\(mediaItem.timestamp.formattedViewerDay()), \(mediaItem.timestamp.formattedTime())"
        guard let position else { return date }
        return "\(date) · \(UntranslatedL10n.screenMediaViewerPosition(position.number, position.count))"
    }
}

extension Date {
    /// "Today", "Yesterday", or the day and month (with the year when it isn't this one), for the viewer's capsule.
    func formattedViewerDay(now: Date = .now) -> String {
        let calendar = Calendar.current
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        if calendar.isDate(self, inSameDayAs: now) || calendar.isDate(self, inSameDayAs: dayBefore) {
            return formattedDateSeparator(now: now)
        } else if calendar.component(.year, from: self) == calendar.component(.year, from: now) {
            return formatted(.dateTime.day().month())
        } else {
            return formatted(.dateTime.day().month().year())
        }
    }
}

// MARK: - Buttons

/// A glass circle with one glyph, 44 pt to tap.
struct MediaViewerGlassButton: View {
    let icon: KeyPath<CompoundIcons, Image>
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MediaViewerGlassGlyph(icon: icon)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct MediaViewerGlassGlyph: View {
    let icon: KeyPath<CompoundIcons, Image>

    var body: some View {
        CompoundIcon(icon, size: .medium, relativeTo: .compound.bodyLG)
            .foregroundStyle(.compound.iconPrimary)
            .frame(width: 44, height: 44)
            .spiralGlass(in: Circle(), isInteractive: true)
            .contentShape(.circle)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

// MARK: - Caption

private struct MediaViewerCaption: View {
    let mediaItem: TimelineMediaPreviewItem.Media

    var body: some View {
        ScrollView(.vertical) {
            captionContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CompoundDesignTokens.space4X)
                .padding(.vertical, CompoundDesignTokens.space3X)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicatorsFlash(onAppear: true)
        .frame(maxHeight: 96)
        .fixedSize(horizontal: false, vertical: true)
        .spiralGlass(in: RoundedRectangle(cornerRadius: SpiralRadius.bubble))
        .padding(.horizontal, CompoundDesignTokens.space4X)
    }

    @ViewBuilder
    private var captionContent: some View {
        if let formattedCaption = mediaItem.formattedCaption {
            FormattedBodyText(attributedString: formattedCaption)
        } else if let caption = mediaItem.caption {
            FormattedBodyText(text: caption)
        }
    }
}
