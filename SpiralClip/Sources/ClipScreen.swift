//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip for invite links (Brief 0086, concept D).
//
// The app's start screen one step earlier: Peek and the name top left, a
// bold headline per page with Spark swiping through the tour, then the
// invitation banner the app's start screen shows after the install and the
// two buttons. The banner and the buttons stay put while the pages swipe.
//

import SpiralTokens
import StoreKit
import SwiftUI

struct ClipScreen: View {
    @Bindable var viewModel: ClipViewModel

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Large text doesn't fit a phone's height: the screen scrolls, and the pages get a height of their own.
                ScrollView {
                    content(pagesHeight: 560, isShortScreen: false)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                GeometryReader { geometry in
                    let isShortScreen = geometry.size.height < Self.shortScreenHeight
                    content(pagesHeight: nil, isShortScreen: isShortScreen)
                        .environment(\.clipIsShortScreen, isShortScreen)
                }
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .appStoreOverlay(isPresented: $viewModel.isShowingInstallOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }

    /// Below this height (an iPhone SE) the headline and spacing tighten, so Spark and the inviter's face keep their size.
    private static let shortScreenHeight: CGFloat = 700

    private func content(pagesHeight: CGFloat?, isShortScreen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ClipBrand()
                .padding(.top, isShortScreen ? 8 : 16)
                .padding(.horizontal, 24)

            ClipPages(viewModel: viewModel)
                .frame(height: pagesHeight)

            VStack(spacing: 12) {
                ClipInviteBanner(state: viewModel.banner, canRetry: viewModel.canRetry) {
                    Task { await viewModel.retry() }
                }

                Button { viewModel.install() } label: {
                    Text("clip.action.install")
                }
                .buttonStyle(ClipCapsuleButtonStyle(kind: .primary))

                Button {
                    openApp()
                } label: {
                    Text("clip.action.have_spiral")
                }
                .buttonStyle(ClipCapsuleButtonStyle(kind: .secondary))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
    }

    /// Inside the Clip the app is usually not installed, so a `spiral://` nobody takes shows the install panel.
    private func openApp() {
        guard let url = viewModel.haveSpiralURL else {
            viewModel.install()
            return
        }
        openURL(url) { accepted in
            if !accepted {
                viewModel.install()
            }
        }
    }
}

private extension EnvironmentValues {
    @Entry var clipIsShortScreen = false
}

// MARK: - Brand

/// Peek's tile at the size of the name, as on the app's start screen.
private struct ClipBrand: View {
    @ScaledMetric(relativeTo: .title3) private var logoSize = 40
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image("app-logo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .overlay {
                    RoundedRectangle(cornerRadius: 0.26 * logoSize, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? .white.opacity(0.16) : .black.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: colorScheme == .light ? .black.opacity(0.14) : .clear, radius: 2.5, y: 1)
                .accessibilityHidden(true)

            Text(verbatim: "Spiral")
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - Pages

private struct ClipPages: View {
    @Bindable var viewModel: ClipViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.clipIsShortScreen) private var isShortScreen

    var body: some View {
        VStack(spacing: isShortScreen ? 12 : 16) {
            TabView(selection: $viewModel.selectedPage) {
                ForEach(ClipPage.allCases) { page in
                    ClipPageView(page: page,
                                 isSelected: viewModel.selectedPage == page,
                                 inviterAvatar: page == .invite ? viewModel.inviterAvatar : nil)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            ClipPager(selectedPage: viewModel.selectedPage) { page in
                withAnimation(reduceMotion ? nil : .default) {
                    viewModel.selectedPage = page
                }
            } next: {
                viewModel.showNextPage()
            } previous: {
                viewModel.showPreviousPage()
            }
        }
        .padding(.bottom, isShortScreen ? 16 : 24)
    }
}

private struct ClipPageView: View {
    let page: ClipPage
    let isSelected: Bool
    let inviterAvatar: ClipInviterAvatar?

    @Environment(\.clipIsShortScreen) private var isShortScreen

    var body: some View {
        // The headline and Spark side by side with the space there is; when large text leaves too little, the page scrolls.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
                .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(page.title)
                .font(isShortScreen ? .title.bold() : .largeTitle.bold())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(page.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ClipSpark(page: page, isSelected: isSelected, inviterAvatar: inviterAvatar)
                .frame(minHeight: 140, idealHeight: 140, maxHeight: 420)
                // Centred in the room the headline leaves.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, isShortScreen ? 8 : 16)
        }
        .padding(.top, isShortScreen ? 16 : 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Spark's pose for the page, with a small hop when its page comes in (none with Reduce Motion). On the invitation
/// page the card carries the inviter's picture.
private struct ClipSpark: View {
    let page: ClipPage
    let isSelected: Bool
    let inviterAvatar: ClipInviterAvatar?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hop = false

    var body: some View {
        Image(page.imageName)
            .resizable()
            .scaledToFit()
            .overlay {
                if let inviterAvatar {
                    GeometryReader { geometry in
                        let rect = ClipPage.inviterAvatarRect
                        ClipInviterAvatarView(avatar: inviterAvatar)
                            .frame(width: rect.width * geometry.size.width, height: rect.height * geometry.size.height)
                            .position(x: rect.midX * geometry.size.width, y: rect.midY * geometry.size.height)
                    }
                    // The rect is measured on the image, which right to left doesn't mirror.
                    .environment(\.layoutDirection, .leftToRight)
                }
            }
            .scaleEffect(hop ? 1.04 : 1)
            // The headline above already says the page; only the inviter on page 1's card is worth a word.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHidden(inviterAvatar == nil)
            .onChange(of: isSelected) { _, isSelected in
                guard isSelected, !reduceMotion else { return }
                withAnimation(.spring(duration: 0.25, bounce: 0.4)) { hop = true }
                withAnimation(.spring(duration: 0.35, bounce: 0.3).delay(0.2)) { hop = false }
            }
    }

    private var accessibilityLabel: String {
        inviterAvatar.map { String(localized: "clip.banner.invited_by \($0.name)") } ?? ""
    }
}

/// The page dots: the current one is a short capsule. One adjustable element for VoiceOver.
private struct ClipPager: View {
    let selectedPage: ClipPage
    let select: (ClipPage) -> Void
    let next: () -> Void
    let previous: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ClipPage.allCases) { page in
                Capsule()
                    .fill(page == selectedPage ? Color("accent-fill") : Color(uiColor: .systemGray4))
                    .frame(width: page == selectedPage ? 18 : 6, height: 6)
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { select(page) }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("clip.a11y.pager"))
        .accessibilityValue(Text("clip.a11y.pager_value \(selectedPage.rawValue + 1) \(ClipPage.allCases.count)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: next()
            case .decrement: previous()
            @unknown default: break
            }
        }
    }
}

/// The inviter's picture, or until it loads or when there is none their monogram, drawn as the app's
/// `PlaceholderAvatarImage` draws it (`AvatarMonogramBackground`): the same gradient, initial and sizes.
private struct ClipInviterAvatarView: View {
    let avatar: ClipInviterAvatar

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(colors: ClipMonogram.stops(diameter: side), startPoint: .top, endPoint: .bottom)
                if let image = avatar.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Part of the picture, so it scales with Spark rather than with Dynamic Type. White is Compound's
                    // textOnSolidPrimary, white in both themes.
                    Text(verbatim: avatar.initial)
                        .font(.system(size: side * 0.5625, weight: .semibold))
                        .minimumScaleFactor(0.001)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: max(1.5, side * 0.05)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum ClipMonogram {
    /// `AvatarMonogramBackground.stops`: the darker stops below 52 pt, where the initial is small text and needs 4.5:1.
    static func stops(diameter: CGFloat) -> [Color] {
        if diameter < SpiralAvatarSize.medium {
            [.spiral.avatarMonogramSmallTop, .spiral.avatarMonogramSmallBottom]
        } else {
            [.spiral.avatarMonogramTop, .spiral.avatarMonogramBottom]
        }
    }
}

// MARK: - Banner

/// The app's start-screen invitation banner, with the Clip's states.
struct ClipInviteBanner: View {
    let state: ClipBannerState
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.body)
                .foregroundStyle(iconStyle)
                .frame(minWidth: 24)
                .accessibilityHidden(true)

            ZStack(alignment: .topLeading) {
                // Reserves two title lines and a hint line in every state, so a long name, an error or the
                // answer replacing the placeholder never moves Spark.
                lines(title: "X\nX", hint: "X")
                    .hidden()
                    .accessibilityHidden(true)
                lines(title: title, hint: hint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .redacted(reason: state == .loading ? .placeholder : [])
            .accessibilityLabel(state == .loading ? Text("clip.banner.loading") : Text(verbatim: "\(title), \(hint)"))

            if canRetry {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color("accent-icon"))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .padding(.vertical, -12)
                .padding(.trailing, -8)
                .accessibilityLabel(Text("clip.action.retry"))
            }
        }
        .padding(16)
        .background(Color("grouped-fill"), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func lines(title: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var iconName: String {
        switch state {
        case .loading, .invited: "person.badge.plus"
        case .noInvitation: "arrow.down.app"
        case .unavailable: "exclamationmark.circle"
        case .couldNotCheck(let isOffline): isOffline ? "wifi.slash" : "exclamationmark.circle"
        }
    }

    private var iconStyle: Color {
        switch state {
        case .loading, .invited, .noInvitation: Color("accent-icon")
        case .unavailable, .couldNotCheck: .secondary
        }
    }

    private var title: String {
        switch state {
        case .invited(let inviterName?): String(localized: "clip.banner.invited_by \(inviterName)")
        case .loading, .invited: String(localized: "clip.banner.invited")
        case .noInvitation: String(localized: "clip.banner.welcome.title")
        case .unavailable: String(localized: "clip.banner.unavailable.title")
        case .couldNotCheck(let isOffline):
            isOffline ? String(localized: "clip.banner.offline.title") : String(localized: "clip.banner.unreadable.title")
        }
    }

    private var hint: String {
        switch state {
        case .loading, .invited: String(localized: "clip.banner.invited.hint")
        case .noInvitation: String(localized: "clip.banner.welcome.hint")
        case .unavailable: String(localized: "clip.banner.unavailable.hint")
        case .couldNotCheck: String(localized: "clip.banner.offline.hint")
        }
    }
}

// MARK: - Buttons

/// Spiral's large capsule buttons: the one blue action and the quiet grey one.
private struct ClipCapsuleButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(kind == .primary ? Color.white : Color.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(kind == .primary ? Color("accent-fill") : Color("grouped-fill"), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

// MARK: - Previews

struct ClipScreen_Previews: PreviewProvider {
    static var previews: some View {
        ClipScreen(viewModel: .preview(.invited(inviterName: "Alice"), token: "Qz8Hf72Kd91", avatar: ClipInviterAvatar(name: "Alice")))
            .previewDisplayName("Invited, monogram")
        ClipScreen(viewModel: .preview(.invited(inviterName: "Alice"),
                                       token: "Qz8Hf72Kd91",
                                       avatar: ClipInviterAvatar(name: "Alice", image: UIImage(named: "app-logo"))))
            .previewDisplayName("Invited, picture")
        ClipScreen(viewModel: .preview(.invited(inviterName: "Alice"),
                                       token: "Qz8Hf72Kd91",
                                       avatar: ClipInviterAvatar(name: "Alice", image: UIImage(named: "app-logo"))))
            .previewDevice("iPhone SE (3rd generation)")
            .previewDisplayName("iPhone SE")
        ClipScreen(viewModel: .preview(.loading, token: "Qz8Hf72Kd91"))
            .previewDisplayName("Loading")
        ClipScreen(viewModel: .preview(.invited(inviterName: nil), token: "TESTFLIGHT"))
            .previewDisplayName("Campaign")
        ClipScreen(viewModel: .preview(.unavailable, token: nil))
            .previewDisplayName("No longer valid")
        ClipScreen(viewModel: .preview(.couldNotCheck(isOffline: true), token: "Qz8Hf72Kd91"))
            .previewDisplayName("Offline")
        ClipScreen(viewModel: .preview(.couldNotCheck(isOffline: false), token: "Qz8Hf72Kd91"))
            .previewDisplayName("Could not check")
        ClipScreen(viewModel: .preview(.noInvitation, token: nil))
            .previewDisplayName("No invitation")
        ClipScreen(viewModel: .preview(.invited(inviterName: "Alice"), token: "Qz8Hf72Kd91", page: .calls))
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark, calls")
        ClipScreen(viewModel: .preview(.invited(inviterName: "أحمد"), token: "Qz8Hf72Kd91", avatar: ClipInviterAvatar(name: "أحمد")))
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .previewDisplayName("Right to left")
        ClipScreen(viewModel: .preview(.couldNotCheck(isOffline: true), token: "Qz8Hf72Kd91"))
            .dynamicTypeSize(.accessibility2)
            .previewDisplayName("Largest text")
    }
}

extension ClipViewModel {
    static func preview(_ banner: ClipBannerState, token: String?, avatar: ClipInviterAvatar? = nil, page: ClipPage = .invite) -> ClipViewModel {
        let viewModel = ClipViewModel(handOff: nil,
                                      resolver: PreviewResolver(),
                                      avatarLoader: PreviewAvatarLoader(),
                                      banner: banner,
                                      token: token,
                                      inviterAvatar: avatar)
        viewModel.selectedPage = page
        return viewModel
    }

    private struct PreviewResolver: ClipInviteResolverProtocol {
        func resolve(token: String) async -> ClipInviteResolution {
            .valid(inviterDisplayName: "Alice", inviterUserID: nil, inviterAvatarURL: nil)
        }
    }

    private struct PreviewAvatarLoader: ClipAvatarLoaderProtocol {
        func image(at url: URL) async -> UIImage? {
            nil
        }
    }
}
