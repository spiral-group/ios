//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A feed post built from leaf views only —
// SwiftUI `Text`, `LoadableImage`, `LoadableAvatarImage` and the session's
// media provider. The room-bound timeline types are avoided
// (`TimelineStyler`, `GalleryGridView`, pills): a feed post has no room.
//

import Compound
import SpiralTokens
import SwiftUI

enum FeedPostCardAction: Equatable {
    case openPost
    case openAuthor
    /// The post-level "Show" of a sensitive post.
    case reveal
    case openMedia(index: Int)
    // Lane I3.
    case like
    case comment
    case share
    case hide
    /// Lane I3 on B4: the report screen for this post.
    case report
    /// Lane I5: who liked it, from the count.
    case openLikers
}

struct FeedPostCard: View {
    enum Style {
        /// The column beside the avatar, as decision 338 chose for a list.
        case list
        /// The whole width, the words a step larger, no menu: the screen's bar holds the same actions.
        case opened
        /// Latest's pinned post (concept A): a list post on its own faintly tinted card, "Pinned" inside it and the text
        /// cut to a few lines with "Read more"; the whole post is one tap away.
        case pinned
    }

    private static let openedStepLimit = 280
    /// The pinned post's lines before "Read more".
    static let pinnedLineLimit = 4

    let model: FeedPostCardModel
    let isRevealed: Bool
    let mediaProvider: MediaProviderProtocol?
    /// The likes count opens who liked (lane I5); off where no sheet can open over the list.
    var showsLikers = true
    /// A `FeedPostMarker` sits right above it, so the post starts closer to it.
    var isMarked = false
    /// The post as a list draws it, or opened on its own screen.
    var style = Style.list
    let action: (FeedPostCardAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    /// Brief 0083 (decision 338): in a list the post's text, media and buttons take the column after the avatar, as
    /// Threads and X draw a post. Opened, or at accessibility sizes, they take the whole width.
    private var isIndented: Bool {
        style != .opened && !dynamicTypeSize.isAccessibilitySize
    }

    private var isPinned: Bool {
        style == .pinned
    }

    var body: some View {
        if model.isAvailable {
            card
        } else {
            // No author, no tap: nothing of the post is shown.
            FeedNoticeBox(text: UntranslatedL10n.screenFeedPostNotAvailableTitle)
                .padding(CompoundDesignTokens.space4X)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.postCard)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space1_5X) {
            if isPinned {
                FeedPinnedLabel()
                    .padding(.leading, isIndented ? Self.textColumnInset : 0)
            }
            layout
        }
        .padding(.horizontal, isPinned ? CompoundDesignTokens.space3X : CompoundDesignTokens.space4X)
        .padding(.top, isMarked ? CompoundDesignTokens.space2X : CompoundDesignTokens.space3X)
        .padding(.bottom, model.engagement == nil ? CompoundDesignTokens.space3X : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .feedPinnedCard(isPinned)
        .contentShape(isPinned ? AnyShape(.rect(cornerRadius: SpiralRadius.listCard)) : AnyShape(.rect))
        .onTapGesture { action(.openPost) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action(.openPost) }
        .accessibilityActions { accessibilityActions }
        .accessibilityIdentifier(A11yIdentifiers.feedScreen.postCard)
    }

    /// Where the text column starts: past the avatar and the gap after it.
    private static var textColumnInset: CGFloat {
        Avatars.Size.user(on: .timeline).value + CompoundDesignTokens.space3X
    }

    @ViewBuilder
    private var layout: some View {
        Group {
            if isIndented {
                HStack(alignment: .top, spacing: CompoundDesignTokens.space3X) {
                    authorButton {
                        // A 44 pt target around the 32 pt avatar, reaching into the margin and the gap.
                        avatar
                            .padding(CompoundDesignTokens.space1_5X)
                            .contentShape(.rect)
                    }
                    .padding(-CompoundDesignTokens.space1_5X)
                    .accessibilityIdentifier(A11yIdentifiers.feedScreen.postAuthor)
                    VStack(alignment: .leading, spacing: CompoundDesignTokens.space1X) {
                        headerRow { authorButton { nameAndTime } }
                        details
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
                    headerRow {
                        authorButton {
                            HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: CompoundDesignTokens.space3X) {
                                avatar
                                nameAndTime
                            }
                        }
                        .accessibilityIdentifier(A11yIdentifiers.feedScreen.postAuthor)
                    }
                    details
                }
            }
        }
    }

    /// VoiceOver says a pinned post is pinned before whose it is.
    private var accessibilityLabel: String {
        let label = model.accessibilityLabel(isRevealed: isRevealed)
        return isPinned ? "\(UntranslatedL10n.screenFeedPinnedLabel), \(label)" : label
    }

    @ViewBuilder
    private var details: some View {
        content
        if let engagement = model.engagement {
            FeedEngagementBar(engagement: engagement, canShare: model.canShare(isRevealed: isRevealed), showsLikers: showsLikers, action: action)
        }
    }

    // MARK: - Header

    /// The author, then the post's menu at the trailing end, as Threads and X place it (it was beside the buttons).
    private func headerRow(@ViewBuilder author: () -> some View) -> some View {
        HStack(alignment: isIndented ? .firstTextBaseline : .center, spacing: CompoundDesignTokens.space2X) {
            author()
                .layoutPriority(1) // The spacer would otherwise take half the row, and break a name at accessibility sizes.
            Spacer(minLength: 0)
            if style != .opened, let engagement = model.engagement {
                FeedPostMenu(engagement: engagement, action: action)
            }
        }
    }

    private func authorButton(@ViewBuilder label: () -> some View) -> some View {
        Button { action(.openAuthor) } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    private var avatar: some View {
        LoadableAvatarImage(url: model.authorAvatarURL,
                            name: model.authorName,
                            contentID: model.authorID,
                            avatarSize: .user(on: .timeline),
                            mediaProvider: mediaProvider)
            .accessibilityHidden(true)
    }

    /// The name and the time on one line, as quiet as the name is plain; under each other at accessibility sizes.
    private var nameAndTime: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1_5X))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space1X) {
                Text(model.authorName)
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(.compound.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                if model.isOfficial {
                    FeedOfficialSeal()
                }
            }
            FeedShortTime(date: model.createdAt)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textSecondary)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isSensitive, !isRevealed {
            FeedSensitiveCover { action(.reveal) }
        } else {
            switch model.body {
            case .content(let text, let media):
                if let text {
                    if isPinned {
                        FeedClampedText(text: text, lineLimit: Self.pinnedLineLimit)
                    } else {
                        FeedCardText(text: text, font: textFont(for: text))
                    }
                }
                if !media.isEmpty {
                    FeedMediaGrid(media: media, mediaProvider: mediaProvider) { index in
                        action(.openMedia(index: index))
                    }
                    .padding(.top, isIndented ? CompoundDesignTokens.space1X : 0)
                }
            case .unsupported:
                FeedNoticeBox(text: UntranslatedL10n.screenFeedPostUnsupported)
            case .notAvailable:
                EmptyView() // Drawn by `body` instead.
            }
        }
    }

    /// A step larger when opened, except a long post, which 20 pt makes heavy.
    private func textFont(for text: AttributedString) -> Font {
        style == .opened && text.characters.count <= Self.openedStepLimit ? .compound.headingSM : .compound.bodyLG
    }

    // MARK: - VoiceOver

    /// No "Read more" on the pinned card: VoiceOver reads its whole text from the label, and activation opens the post.
    @ViewBuilder
    private var accessibilityActions: some View {
        Button(UntranslatedL10n.a11yFeedOpenAuthor(model.authorName)) { action(.openAuthor) }
        if model.isSensitive, !isRevealed {
            Button(UntranslatedL10n.screenFeedSensitiveShow) { action(.reveal) }
        } else {
            ForEach(Array(model.media.enumerated()), id: \.offset) { index, media in
                Button(media.altText.map { UntranslatedL10n.a11yFeedOpenImageWithAlt(index + 1, $0) } ?? UntranslatedL10n.a11yFeedOpenImage(index + 1)) {
                    action(.openMedia(index: index))
                }
            }
            ForEach(model.links, id: \.self) { url in
                // A sighted tap on a link is handled by the text; VoiceOver reads the card as one element.
                Button(UntranslatedL10n.a11yFeedOpenLink(url.host() ?? url.absoluteString)) { openURL(url) }
            }
        }
        if let engagement = model.engagement {
            Button(engagement.isLiked ? UntranslatedL10n.a11yFeedUnlike : UntranslatedL10n.a11yFeedLike) { action(.like) }
            if showsLikers, engagement.likes > 0 {
                Button(UntranslatedL10n.a11yFeedShowLikers) { action(.openLikers) }
            }
            if engagement.commentsEnabled {
                Button(UntranslatedL10n.a11yFeedComment) { action(.comment) }
            }
            if model.canShare(isRevealed: isRevealed) {
                Button(UntranslatedL10n.screenFeedShareAction) { action(.share) }
            }
            if engagement.canHide {
                Button(UntranslatedL10n.screenFeedHideAction) { action(.hide) }
            }
            if engagement.canReport {
                Button(UntranslatedL10n.screenFeedReportPostAction) { action(.report) }
            }
        }
    }
}

/// Like, comments and share under a visible post (lane I3), together at the leading edge, each count beside its glyph.
/// A sighted tap on a button wins over the card's tap; VoiceOver reaches the same actions through the card's custom actions.
///
/// Brief 0083: a target starts at its glyph, so the glyphs sit close: a count shows only above zero. The heart's 44 pt
/// target reaches into the margin, keeping its glyph on the text's edge, and ends where the digits begin. A short count's
/// own target is 32 × 44: the operator asked for the actions together.
struct FeedEngagementBar: View {
    /// What the heart's target reaches past its glyph into the margin.
    private static let leadingReach = CompoundDesignTokens.space5X

    let engagement: FeedPostCardModel.Engagement
    /// Off for a sensitive post until it is shown (decision 267).
    let canShare: Bool
    /// A count above zero opens who liked (lane I5).
    var showsLikers = true
    let action: (FeedPostCardAction) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The space after a glyph or a count, inside its button; at accessibility sizes the row needs it to stay one row.
    private var trailingSpace: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? CompoundDesignTokens.space2X : CompoundDesignTokens.space5X
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                buttons
            }
            VStack(alignment: .leading, spacing: 0) {
                buttons
            }
        }
        .padding(.leading, -Self.leadingReach)
        .font(.compound.bodyMD)
        .foregroundStyle(.compound.textSecondary)
        .buttonStyle(FeedPressButtonStyle())
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 0) {
            Button { action(.like) } label: {
                // Compound has no heart; a like reads as one everywhere else.
                CompoundIcon(customImage: Image(systemName: engagement.isLiked ? "heart.fill" : "heart"), size: .small, relativeTo: .compound.bodyMD)
                    .symbolEffect(.bounce, value: engagement.isLiked)
                    .foregroundStyle(engagement.isLiked ? .compound.iconCriticalPrimary : .compound.iconSecondary)
                    .padding(.leading, Self.leadingReach)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
            }
            .accessibilityIdentifier(A11yIdentifiers.feedScreen.like)

            // The count is its own tap (lane I5): who liked, as on Threads and Instagram.
            if engagement.likes > 0 {
                Button { action(showsLikers ? .openLikers : .like) } label: {
                    Text(engagement.likes, format: .number)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(engagement.likes)))
                        .animation(.default, value: engagement.likes)
                        .padding(.trailing, trailingSpace)
                        .frame(minWidth: CompoundDesignTokens.space8X, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                }
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.likesCount)
            } else {
                Spacer()
                    .frame(width: trailingSpace)
            }
        }

        if engagement.commentsEnabled {
            Button { action(.comment) } label: {
                counted(engagement.comments, icon: \.chat)
            }
            .accessibilityIdentifier(A11yIdentifiers.feedScreen.comment)
        }

        Button { action(.share) } label: {
            counted(engagement.shares, icon: \.shareIos)
        }
        .disabled(!canShare)
        .accessibilityIdentifier(A11yIdentifiers.feedScreen.share)
    }

    private func counted(_ count: Int, icon: KeyPath<CompoundIcons, Image>) -> some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            CompoundIcon(icon, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconSecondary)
            if count > 0 {
                Text(count, format: .number)
                    .monospacedDigit()
            }
        }
        .padding(.trailing, trailingSpace)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
    }
}

/// Hide and Report behind "…" at the post's top trailing corner (lane I3); its target reaches 12 pt past the glyph,
/// into the margin.
private struct FeedPostMenu: View {
    let engagement: FeedPostCardModel.Engagement
    let action: (FeedPostCardAction) -> Void

    var body: some View {
        if engagement.canHide || engagement.canReport {
            Menu {
                if engagement.canHide {
                    Button { action(.hide) } label: {
                        Label(UntranslatedL10n.screenFeedHideAction, icon: \.visibilityOff)
                    }
                }
                if engagement.canReport {
                    Button { action(.report) } label: {
                        Label(UntranslatedL10n.screenFeedReportPostAction, icon: \.chatProblem)
                    }
                    .accessibilityIdentifier(A11yIdentifiers.feedScreen.report)
                }
            } label: {
                CompoundIcon(\.overflowHorizontal, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundStyle(.compound.iconSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityLabel(UntranslatedL10n.a11yFeedPostOptions)
            }
            .padding(.trailing, -CompoundDesignTokens.space3X)
            .padding(.vertical, -CompoundDesignTokens.space3X)
            .accessibilityIdentifier(A11yIdentifiers.feedScreen.postMenu)
        }
    }
}

/// A card's text, in SwiftUI's `Text`: a tap outside a link reaches the card's
/// tap and opens the post, a tap on a link opens it through the app's `openURL`.
/// The chat's `MessageText` is a selectable `UITextView` whose recognisers took
/// every tap on the text; the card needs neither its pills (feed text has
/// http(s) links only) nor selection (the post screen has the full text).
struct FeedCardText: View {
    let text: AttributedString
    var font = Font.compound.bodyLG

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(.compound.textPrimary)
            .tint(.compound.textLinkExternal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(A11yIdentifiers.feedScreen.postText)
    }
}

/// "Official" with a check, beside the name of Spiral's labelled account (D-P1). Brief 0083: the seal in the
/// accent and the word in grey, as iOS marks a verified name; the word in the accent read as a link.
struct FeedOfficialLabel: View {
    var body: some View {
        HStack(spacing: CompoundDesignTokens.space1X) {
            CompoundIcon(\.verified, size: .xSmall, relativeTo: .compound.bodySM)
                .foregroundStyle(.compound.iconAccentPrimary)
                .accessibilityHidden(true)
            Text(UntranslatedL10n.screenFeedOfficialLabel)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
        }
    }
}

/// The seal alone beside a name in a list, where "Official" would crowd the line. VoiceOver still says the word.
struct FeedOfficialSeal: View {
    var body: some View {
        CompoundIcon(\.verified, size: .xSmall, relativeTo: .compound.bodyMD)
            .foregroundStyle(.compound.iconAccentPrimary)
            .accessibilityLabel(UntranslatedL10n.screenFeedOfficialLabel)
    }
}

/// The text of a box that stands in for a post's content.
struct FeedNoticeBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.compound.bodyMD)
            .foregroundStyle(.compound.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(CompoundDesignTokens.space3X)
            .background(.compound.bgSubtleSecondary, in: .rect(cornerRadius: SpiralRadius.block))
    }
}

/// One cover over the whole of a sensitive post, text and images together
/// (spike caveat 1: a "Show" per tile took four taps).
private struct FeedSensitiveCover: View {
    let reveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(UntranslatedL10n.screenFeedSensitiveTitle)
                    .font(.compound.bodyMDSemibold)
                    .foregroundStyle(.compound.textPrimary)
            } icon: {
                CompoundIcon(\.visibilityOff, size: .small, relativeTo: .compound.bodyMDSemibold)
                    .foregroundStyle(.compound.iconSecondary)
            }
            Text(UntranslatedL10n.screenFeedSensitiveMessage)
                .font(.compound.bodySM)
                .foregroundStyle(.compound.textSecondary)
            Button(UntranslatedL10n.screenFeedSensitiveShow, action: reveal)
                .buttonStyle(.compound(.secondary, size: .small, isRaised: true)) // On the box's grey (decision 329).
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CompoundDesignTokens.space3X)
        .background(.compound.bgSubtleSecondary, in: .rect(cornerRadius: SpiralRadius.block))
    }
}

/// One to four images: 1, 2 side by side, 1 + 2, or 2 × 2. Rendering only;
/// the composer that makes them is lane I4.
struct FeedMediaGrid: View {
    let media: [FeedPostCardModel.Media]
    let mediaProvider: MediaProviderProtocol?
    let open: (Int) -> Void

    private let spacing: CGFloat = 2
    /// The server is asked for ~1080 px thumbnails (spike caveat 2).
    private static let thumbnailSide: CGFloat = 1080

    var body: some View {
        grid
            .clipShape(.rect(cornerRadius: SpiralRadius.block))
    }

    @ViewBuilder
    private var grid: some View {
        switch media.count {
        case 1:
            let item = media[0]
            // Clamped so a panorama or a tall screenshot does not take over the feed.
            let ratio = min(max(CGFloat(item.width) / CGFloat(max(item.height, 1)), 0.75), 2)
            tile(0, thumbnail: CGSize(width: Self.thumbnailSide, height: Self.thumbnailSide / ratio))
                .aspectRatio(ratio, contentMode: .fit)
        case 2:
            HStack(spacing: spacing) {
                tile(0)
                tile(1)
            }
            .aspectRatio(2, contentMode: .fit)
        case 3:
            HStack(spacing: spacing) {
                tile(0)
                VStack(spacing: spacing) {
                    tile(1)
                    tile(2)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
        default:
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    tile(0)
                    tile(1)
                }
                HStack(spacing: spacing) {
                    tile(2)
                    tile(3)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private func tile(_ index: Int, thumbnail: CGSize = CGSize(width: thumbnailSide, height: thumbnailSide)) -> some View {
        let item = media[index]
        return Button { open(index) } label: {
            Color.compound.bgSubtleSecondary
                .overlay {
                    if let source = item.source {
                        LoadableImage(mediaSource: source,
                                      mediaType: .generic,
                                      blurhash: item.blurhash,
                                      size: thumbnail,
                                      mediaProvider: mediaProvider) { image in
                            image.scaledToFill()
                        } placeholder: {
                            Color.compound.bgSubtleSecondary
                        }
                    }
                }
                .clipped()
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(item.source == nil)
    }
}

// MARK: - Previews

struct FeedPostCard_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 0) {
                cell(FeedPreviewData.engagedPost)
                cell(FeedPreviewData.officialPost)
                cell(FeedPreviewData.imagePost(count: 1))
                cell(FeedPreviewData.imagePost(count: 2))
                cell(FeedPreviewData.imagePost(count: 3))
                cell(FeedPreviewData.imagePost(count: 4))
                cell(FeedPreviewData.sensitivePost)
                cell(FeedPreviewData.sensitivePost, isRevealed: true)
                cell(FeedPreviewData.unsupportedPost)
            }
        }
        .previewDisplayName("Cards")

        card(FeedPreviewData.officialPost)
            .dynamicTypeSize(.accessibility5)
            .previewDisplayName("AX5")

        VStack(spacing: 0) {
            card(FeedPreviewData.welcomePost.withCounts(likes: 4, comments: 2), style: .pinned)
                .padding(CompoundDesignTokens.space2X)
            card(FeedPreviewData.officialPost, style: .pinned)
                .padding(CompoundDesignTokens.space2X)
        }
        .previewDisplayName("Pinned")

        ScrollView {
            card(FeedPreviewData.welcomePost, style: .pinned)
                .padding(CompoundDesignTokens.space2X)
        }
        .dynamicTypeSize(.accessibility3)
        .previewDisplayName("Pinned AX3")

        card(FeedPreviewData.notAvailablePost)
            .previewDisplayName("Not available")
    }

    private static func cell(_ post: FeedPost, isRevealed: Bool = false) -> some View {
        FeedPostListCell {
            card(post, isRevealed: isRevealed)
        }
    }

    private static func card(_ post: FeedPost, isRevealed: Bool = false, style: FeedPostCard.Style = .list) -> some View {
        FeedPostCard(model: FeedPostCardModel(post: post), isRevealed: isRevealed, mediaProvider: MediaProviderMock(.init()), style: style) { _ in }
    }
}
