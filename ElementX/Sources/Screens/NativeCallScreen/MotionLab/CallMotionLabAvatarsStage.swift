//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (question 390): the agents' own colours, the eight system hues (`AgentAvatarPalette`). A chat list of
// agents without a picture at 52 pt, one on each colour, the same agents at 32, 20 and 16 pt, and beside them two people's
// letters and an agent's own picture. At the bottom, the palette itself in light and dark side by side, each colour
// named with the white Peek's contrast on it. The toggle at the top switches the theme. Every avatar is the app's own
// `LoadableAvatarImage`.
//
// Question 393, at the top: the agent badge, the Peek, on agents' photos at 52, 40, 32 and 24 pt (the badge's floor),
// in light and dark, two of them beside the online dot.
//
// Question 399, first: the tab bar with the person's avatar in its ring, Settings selected and not, light and dark.
//
// `-SpiralCallMotionLabStage Avatars`.
//
// Staging and Debug builds only.

#if DEBUG || SPIRAL_STAGING

import Compound
import SpiralTokens
import SwiftUI

struct CallMotionLabAvatarsStage: View {
    @Binding var theme: CallMotionLabScreen.Theme

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space6X) {
                tabBar
                badges
                chatList
                sizes
                palette
            }
            .padding(.vertical, CompoundDesignTokens.space4X)
        }
        .safeAreaInset(edge: .top) { controls }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
    }

    // MARK: - Views

    /// The theme, clear of the lab's Controls button in the top trailing corner.
    private var controls: some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            Picker("Theme", selection: isDark) {
                Text("Light").tag(false)
                Text("Dark").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            Spacer(minLength: 0)
        }
        .padding(.leading, CompoundDesignTokens.space4X)
        .padding(.trailing, 56)
        .padding(.vertical, CompoundDesignTokens.space2X)
    }

    /// Question 399: the real tab bar, Settings selected and not, in light and in dark.
    private var tabBar: some View {
        section("Tab bar · question 399") {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
                tabBarSheet(.light)
                tabBarSheet(.dark)
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
        }
    }

    private func tabBarSheet(_ scheme: ColorScheme) -> some View {
        VStack(spacing: 0) {
            CallMotionLabTabBar(selection: .settings)
            CallMotionLabTabBar(selection: .agents)
        }
        .padding(.top, CompoundDesignTokens.space4X)
        .padding(.bottom, CompoundDesignTokens.space2X)
        .background(Color.compound.bgCanvasDefault)
        .clipShape(RoundedRectangle(cornerRadius: SpiralRadius.listCard))
        .overlay(RoundedRectangle(cornerRadius: SpiralRadius.listCard).strokeBorder(.compound.borderDisabled))
        .environment(\.colorScheme, scheme)
    }

    /// Question 393: the badge on four photos at each size, in light and in dark.
    private var badges: some View {
        section("Agent badge · question 393") {
            VStack(alignment: .leading, spacing: CompoundDesignTokens.space3X) {
                badgeSheet(.light)
                badgeSheet(.dark)
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
        }
    }

    private func badgeSheet(_ scheme: ColorScheme) -> some View {
        Grid(alignment: .leading, horizontalSpacing: CompoundDesignTokens.space3X, verticalSpacing: CompoundDesignTokens.space3X) {
            Text(scheme == .dark ? "Dark" : "Light")
                .font(.compound.bodyXSSemibold)
                .foregroundStyle(.compound.textSecondary)

            ForEach(Self.badgeSizes, id: \.self) { size in
                GridRow(alignment: .center) {
                    Text("\(Int(size))")
                        .font(.compound.bodyXS)
                        .monospacedDigit()
                        .foregroundStyle(.compound.textSecondary)
                    ForEach(Self.photoAgents) { avatar($0, size: size) }
                }
            }
        }
        .padding(CompoundDesignTokens.space3X)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.compound.bgCanvasDefault, in: RoundedRectangle(cornerRadius: SpiralRadius.listCard))
        .overlay(RoundedRectangle(cornerRadius: SpiralRadius.listCard).strokeBorder(.compound.borderDisabled))
        .environment(\.colorScheme, scheme)
    }

    private var chatList: some View {
        section("Chats · 52 pt") {
            VStack(spacing: 0) {
                ForEach(Self.agents) { row($0) }
                Divider()
                    .padding(.vertical, CompoundDesignTokens.space2X)
                ForEach(Self.comparison) { row($0) }
            }
        }
    }

    private var sizes: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space6X) {
            ForEach(Self.smallSizes, id: \.self) { size in
                section("\(Int(size)) pt") {
                    ScrollView(.horizontal) {
                        HStack(spacing: size < SpiralAvatarSize.xSmall ? CompoundDesignTokens.space2X : CompoundDesignTokens.space3X) {
                            ForEach(Self.agents + Self.comparison) { avatar($0, size: size) }
                        }
                        .padding(.horizontal, CompoundDesignTokens.space4X)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    /// The palette on its own, light beside dark in the same order: each colour, its name and the white Peek's contrast.
    private var palette: some View {
        section("System hues: \(AgentAvatarPalette.gradients.count) colours") {
            HStack(alignment: .top, spacing: CompoundDesignTokens.space3X) {
                swatches(.light)
                swatches(.dark)
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
        }
    }

    private func swatches(_ scheme: ColorScheme) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: CompoundDesignTokens.space3X) {
            ForEach(AgentAvatarPalette.gradients) { gradient in
                let stops = scheme == .dark ? gradient.dark : gradient.light
                VStack(spacing: CompoundDesignTokens.space1X) {
                    ZStack {
                        LinearGradient(colors: gradient.colors, startPoint: .top, endPoint: .bottom)
                        Image(asset: Asset.spiralPeekFill)
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.compound.textOnSolidPrimary)
                            .padding(9)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    Text(gradient.name)
                        .font(.compound.bodyXSSemibold)
                        .foregroundStyle(.compound.textPrimary)
                    Text(String(format: "%.1f:1", stops.whiteContrast))
                        .font(.compound.bodyXS)
                        .monospacedDigit()
                        .foregroundStyle(.compound.textSecondary)
                }
            }
        }
        .padding(CompoundDesignTokens.space3X)
        .background(Color.compound.bgCanvasDefault, in: RoundedRectangle(cornerRadius: SpiralRadius.listCard))
        .overlay(RoundedRectangle(cornerRadius: SpiralRadius.listCard).strokeBorder(.compound.borderDisabled))
        .environment(\.colorScheme, scheme)
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: CompoundDesignTokens.space3X) {
            avatar(entry, size: SpiralAvatarSize.medium)

            VStack(alignment: .leading, spacing: CompoundDesignTokens.space0_5X) {
                HStack(alignment: .firstTextBaseline, spacing: CompoundDesignTokens.space2X) {
                    Text(entry.name)
                        .font(.compound.bodyLGSemibold)
                        .foregroundStyle(.compound.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(colourName(entry))
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                }
                Text(entry.line)
                    .font(.compound.bodyMD)
                    .foregroundStyle(.compound.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, CompoundDesignTokens.space4X)
        .padding(.vertical, CompoundDesignTokens.space2X)
    }

    private func avatar(_ entry: Entry, size: CGFloat) -> some View {
        LoadableAvatarImage(url: entry.avatarURL,
                            name: entry.name,
                            contentID: entry.userID,
                            avatarSize: .custom(size),
                            mediaProvider: Self.mediaProvider)
            .avatarBadges(userID: entry.userID, avatarURL: entry.avatarURL, isOnline: entry.isOnline, avatarSize: size, announced: false)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space2X) {
            Text(title)
                .font(.compound.bodySMSemibold)
                .foregroundStyle(.compound.textSecondary)
                .padding(.horizontal, CompoundDesignTokens.space4X)
            content()
        }
    }

    // MARK: - Private

    private var isDark: Binding<Bool> {
        Binding { colorScheme == .dark } set: { theme = $0 ? .dark : .light }
    }

    /// Which of the palette's colours an agent without a picture got; the others draw no Peek.
    private func colourName(_ entry: Entry) -> String {
        guard entry.avatarURL == nil, AgentAvatar.fallback(contentID: entry.userID) == .peek else { return "" }
        return AgentAvatarPalette.gradient(for: entry.userID).name
    }

    private struct Entry: Identifiable {
        let userID: String
        let name: String
        let line: String
        var avatarURL: URL?
        var isOnline = false

        var id: String {
            userID
        }
    }

    /// Fictional agents in both namespaces, on one server, as an owner's chat list has them; their IDs land on the
    /// eight colours in turn.
    private static let agents = [
        Entry(userID: "@assistant-alex:spiral.example", name: "Alex Sample · assistant", line: "Your 10:30 moved to Thursday", isOnline: true),
        Entry(userID: "@assistant-mira:spiral.example", name: "Mira Testova · assistant", line: "I sent the summary to the group"),
        Entry(userID: "@agent-translator:spiral.example", name: "Translator", line: "Done: English → Ukrainian"),
        Entry(userID: "@agent-news:spiral.example", name: "News", line: "Three stories you follow"),
        Entry(userID: "@agent-weather:spiral.example", name: "Weather", line: "Rain after four"),
        Entry(userID: "@assistant-sam:spiral.example", name: "Sam Example · assistant", line: "Want me to reply for you?"),
        Entry(userID: "@agent-support:spiral.example", name: "Support", line: "Your ticket is closed"),
        Entry(userID: "@assistant-kim:spiral.example", name: "Kim Example · assistant", line: "Saved to “Kitchen ideas”")
    ]

    /// Two people's letters, on 328's monogram, and an agent with a picture of its own and its badge.
    private static let comparison = [
        Entry(userID: "@lena:spiral.example", name: "Lena Example", line: "See you at six", isOnline: true),
        Entry(userID: "@omar:spiral.example", name: "Omar Sample", line: "Photo"),
        Entry(userID: "@agent-concierge:spiral.example", name: "Concierge", line: "The table is booked", avatarURL: .mockMXCUserAvatar)
    ]

    /// Agents with photos of their own, light and dark, busy and plain, for the badge's plate to hold its glyph over;
    /// the first, on a dark photo, and the last, on a light one, are online, so their dots sit beside the badge.
    private static let photoAgents = [
        Entry(userID: "@agent-concierge:spiral.example", name: "Concierge", line: "", avatarURL: .mockMXCUserAvatar, isOnline: true),
        Entry(userID: "@agent-florist:spiral.example", name: "Florist", line: "", avatarURL: .mockMXCAvatar),
        Entry(userID: "@assistant-noa:spiral.example", name: "Noa Example", line: "", avatarURL: .mockMXCImage),
        Entry(userID: "@agent-studio:spiral.example", name: "Studio", line: "", avatarURL: .mockMXCVideo, isOnline: true)
    ]

    /// List rows, 40, the timeline's senders and the badge's floor.
    private static let badgeSizes: [CGFloat] = [SpiralAvatarSize.medium, 40, SpiralAvatarSize.small, AgentBadge.smallestAvatarSize]

    /// 32 as in the member list, 20, and the scale's floor, 16.
    private static let smallSizes: [CGFloat] = [SpiralAvatarSize.small, 20, SpiralAvatarSize.xxSmall]
    private static let mediaProvider = MediaProviderMock(.init())
}

/// The app's tab bar with its four tabs, each icon drawn as the app draws it: Spiral's symbols through `TabDetails`, the
/// person's avatar through `SpiralTabAvatar`.
private struct CallMotionLabTabBar: View {
    enum Tag: Hashable { case chats, feed, agents, settings }

    let selection: Tag

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.legibilityWeight) private var legibilityWeight
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TabView(selection: .constant(selection)) {
            ForEach(Self.tabs, id: \.tag) { details in
                Tab(value: details.tag) {
                    Color.clear
                } label: {
                    Label {
                        Text(details.title)
                    } icon: {
                        icon(details)
                    }
                }
            }
        }
        .frame(height: 72)
    }

    @ViewBuilder
    private func icon(_ details: NavigationTabCoordinator<Tag>.TabDetails) -> some View {
        let appearance = SpiralTabAvatar.Appearance(isSelected: details.tag == selection,
                                                    colorScheme: colorScheme,
                                                    colorSchemeContrast: colorSchemeContrast,
                                                    legibilityWeight: legibilityWeight,
                                                    displayScale: displayScale)
        if details.tag == .settings, let image = Self.avatar.image(for: appearance) {
            Image(uiImage: image)
                .renderingMode(.original)
        } else {
            details.iconView(for: appearance)
        }
    }

    private static let tabs: [NavigationTabCoordinator<Tag>.TabDetails] = [
        .init(tag: .chats, title: L10n.screenHomeTabChats, symbol: SpiralTabSymbol.chats),
        .init(tag: .feed, title: UntranslatedL10n.screenHomeTabFeed, symbol: SpiralTabSymbol.feed),
        .init(tag: .agents, title: UntranslatedL10n.screenHomeTabAgents, symbol: SpiralTabSymbol.agents),
        .init(tag: .settings, title: L10n.commonSettings, icon: \.userProfile, selectedIcon: \.userProfileSolid)
    ]

    /// The development assets' person, as the mock media provider serves it; the monogram when the build has none.
    private static let avatar = SpiralTabAvatar(name: "Dan", contentID: "@dan:matrix.org",
                                                photo: Bundle.main.url(forResource: "preview_avatar_user", withExtension: "jpg")
                                                    .flatMap { try? Data(contentsOf: $0) }
                                                    .flatMap(UIImage.init(data:)))
}

#endif
