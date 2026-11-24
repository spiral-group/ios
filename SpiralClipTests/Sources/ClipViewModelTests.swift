//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0086 — the App Clip's states.
//

@testable import SpiralClip
import SpiralTokens
import SwiftUI
import Testing

struct ClipViewModelTests {
    @Test
    func theInvitationIsSavedBeforeTheServerAnswers() async throws {
        let (handOff, _) = try makeHandOff()
        let resolver = ResolverStub(.valid(inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md", inviterAvatarURL: nil))
        resolver.onResolve = { #expect(handOff.read() == ClipInvite(token: "Qz8Hf72Kd91", savedAt: Self.savedAt)) }
        let viewModel = makeViewModel(handOff: handOff, resolver: resolver)

        await viewModel.open(Self.inviteURL)

        #expect(resolver.tokens == ["Qz8Hf72Kd91"])
    }

    @Test
    func aLiveInvitationShowsItsInviterAndAddsThemToTheHandOff() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff, resolver: ResolverStub(.valid(inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md", inviterAvatarURL: nil)))

        await viewModel.open(Self.inviteURL)

        #expect(viewModel.banner == .invited(inviterName: "Alice"))
        #expect(handOff.read() == ClipInvite(token: "Qz8Hf72Kd91", inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md", savedAt: Self.savedAt))
        #expect(viewModel.haveSpiralURL?.absoluteString == "spiral://join/Qz8Hf72Kd91")
    }

    @Test
    func aCampaignInvitationHasNoInviter() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff, resolver: ResolverStub(.valid(inviterDisplayName: nil, inviterUserID: nil, inviterAvatarURL: nil)))

        try await viewModel.open(#require(URL(string: "https://spiral.md/join/TESTFLIGHT")))

        #expect(viewModel.banner == .invited(inviterName: nil))
        #expect(handOff.read() == ClipInvite(token: "TESTFLIGHT", savedAt: Self.savedAt))
    }

    @Test
    func aBlankInviterNameReadsAsACampaign() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff, resolver: ResolverStub(.valid(inviterDisplayName: "  ", inviterUserID: "@x:spiral.md", inviterAvatarURL: nil)))

        await viewModel.open(Self.inviteURL)

        #expect(viewModel.banner == .invited(inviterName: nil))
    }

    @Test
    func aDeadInvitationIsNotKept() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff, resolver: ResolverStub(.unavailable))

        await viewModel.open(Self.inviteURL)

        #expect(viewModel.banner == .unavailable)
        #expect(handOff.read() == nil)
        #expect(viewModel.token == nil)
        #expect(!viewModel.canRetry)
        #expect(viewModel.haveSpiralURL?.absoluteString == "spiral://", "the app opens without a dead token")
    }

    @Test
    func offlineKeepsTheInvitationAndRetries() async throws {
        let (handOff, _) = try makeHandOff()
        let resolver = ResolverStub(.offline, .valid(inviterDisplayName: "Alice", inviterUserID: "@alice:spiral.md", inviterAvatarURL: nil))
        let viewModel = makeViewModel(handOff: handOff, resolver: resolver)

        await viewModel.open(Self.inviteURL)

        #expect(viewModel.banner == .couldNotCheck(isOffline: true))
        #expect(viewModel.canRetry)
        #expect(handOff.read() == ClipInvite(token: "Qz8Hf72Kd91", savedAt: Self.savedAt), "it may still be valid")
        #expect(viewModel.haveSpiralURL?.absoluteString == "spiral://join/Qz8Hf72Kd91")

        await viewModel.retry()

        #expect(resolver.tokens == ["Qz8Hf72Kd91", "Qz8Hf72Kd91"])
        #expect(viewModel.banner == .invited(inviterName: "Alice"))
        #expect(handOff.read()?.savedAt == Self.savedAt, "a retry keeps the first save's time")
    }

    @Test
    func anUnreadableAnswerIsACheckThatFailedNotADeadInvitation() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff, resolver: ResolverStub(.unreadable))

        await viewModel.open(Self.inviteURL)

        #expect(viewModel.banner == .couldNotCheck(isOffline: false))
        #expect(viewModel.canRetry)
        #expect(handOff.read()?.token == "Qz8Hf72Kd91")
    }

    @Test
    func theSameLinkAgainOnlyAsksAgainAfterAFailedCheck() async throws {
        let (handOff, _) = try makeHandOff()
        let resolver = ResolverStub(.valid(inviterDisplayName: "Alice", inviterUserID: nil, inviterAvatarURL: nil), .offline)
        let viewModel = makeViewModel(handOff: handOff, resolver: resolver)

        await viewModel.open(Self.inviteURL)
        await viewModel.open(Self.inviteURL)

        #expect(resolver.tokens.count == 1)
        #expect(viewModel.banner == .invited(inviterName: "Alice"))
    }

    @Test
    func aURLThatIsNotAnInvitationShowsNoBanner() async throws {
        let (handOff, _) = try makeHandOff()
        let resolver = ResolverStub()
        let viewModel = makeViewModel(handOff: handOff, resolver: resolver)

        try await viewModel.open(#require(URL(string: "https://appclip.apple.com/id?p=com.veruslogistics.messenger.Clip")))

        #expect(viewModel.banner == .noInvitation)
        #expect(resolver.tokens.isEmpty)
        #expect(handOff.read() == nil)
        #expect(viewModel.haveSpiralURL?.absoluteString == "spiral://")
    }

    @Test
    func noInvocationShowsNoBannerButALateOneStillWorks() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff, resolver: ResolverStub(.valid(inviterDisplayName: "Alice", inviterUserID: nil, inviterAvatarURL: nil)))
        #expect(viewModel.banner == .loading)

        viewModel.invocationTimedOut()
        #expect(viewModel.banner == .noInvitation)

        await viewModel.open(Self.inviteURL)
        #expect(viewModel.banner == .invited(inviterName: "Alice"))

        viewModel.invocationTimedOut()
        #expect(viewModel.banner == .invited(inviterName: "Alice"), "the timeout never hides a banner")
    }

    // MARK: - The inviter on page 1's card

    @Test
    func theInvitersPictureReplacesTheMonogramOnceLoaded() async throws {
        let (handOff, _) = try makeHandOff()
        let avatarURL = try #require(URL(string: "https://spiral.md/og/u/alice"))
        let avatarLoader = AvatarLoaderStub(image: Self.picture)
        let viewModel = makeViewModel(handOff: handOff,
                                      resolver: ResolverStub(.valid(inviterDisplayName: "alice", inviterUserID: "@alice:spiral.md", inviterAvatarURL: avatarURL)),
                                      avatarLoader: avatarLoader)
        avatarLoader.onLoad = { #expect(viewModel.inviterAvatar == ClipInviterAvatar(name: "alice"), "the monogram shows while it loads") }

        await viewModel.open(Self.inviteURL)

        #expect(avatarLoader.urls == [avatarURL])
        #expect(viewModel.inviterAvatar?.initial == "A")
        #expect(viewModel.inviterAvatar?.image === Self.picture)
    }

    @Test
    func anInviterWithoutAPictureGetsTheMonogram() async throws {
        let (handOff, _) = try makeHandOff()
        let avatarLoader = AvatarLoaderStub(image: Self.picture)
        let viewModel = makeViewModel(handOff: handOff,
                                      resolver: ResolverStub(.valid(inviterDisplayName: " Оля", inviterUserID: "@alice:spiral.md", inviterAvatarURL: nil)),
                                      avatarLoader: avatarLoader)

        await viewModel.open(Self.inviteURL)

        #expect(viewModel.inviterAvatar == ClipInviterAvatar(name: "Оля"))
        #expect(viewModel.inviterAvatar?.initial == "О")
        #expect(avatarLoader.urls.isEmpty)
    }

    @Test
    func theMonogramIsTheAppsPlaceholderAvatar() {
        #expect(ClipMonogram.stops(diameter: 39) == [.spiral.avatarMonogramSmallTop, .spiral.avatarMonogramSmallBottom], "the card's size")
        #expect(ClipMonogram.stops(diameter: 52) == [.spiral.avatarMonogramTop, .spiral.avatarMonogramBottom])
        #expect(ClipInviterAvatar(name: "alice").initial == "A")
        #expect(ClipInviterAvatar(name: "Ölgä").initial == "Ö")
        #expect(ClipInviterAvatar(name: "").initial == "")
    }

    @Test
    func aPictureThatFailsToLoadLeavesTheMonogram() async throws {
        let (handOff, _) = try makeHandOff()
        let avatarURL = try #require(URL(string: "https://spiral.md/og/u/alice"))
        let viewModel = makeViewModel(handOff: handOff,
                                      resolver: ResolverStub(.valid(inviterDisplayName: "Alice", inviterUserID: nil, inviterAvatarURL: avatarURL)),
                                      avatarLoader: AvatarLoaderStub(image: nil))

        await viewModel.open(Self.inviteURL)

        #expect(viewModel.inviterAvatar == ClipInviterAvatar(name: "Alice"))
    }

    @Test
    func aCampaignInvitationLeavesTheCardsSpiral() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff, resolver: ResolverStub(.valid(inviterDisplayName: nil, inviterUserID: nil, inviterAvatarURL: nil)))

        try await viewModel.open(#require(URL(string: "https://spiral.md/join/TESTFLIGHT")))

        #expect(viewModel.inviterAvatar == nil)
    }

    @Test
    func aDeadInvitationRemovesTheInviter() async throws {
        let (handOff, _) = try makeHandOff()
        let viewModel = makeViewModel(handOff: handOff,
                                      resolver: ResolverStub(.valid(inviterDisplayName: "Alice", inviterUserID: nil, inviterAvatarURL: nil), .unavailable))
        await viewModel.open(Self.inviteURL)
        #expect(viewModel.inviterAvatar != nil)

        try await viewModel.open(#require(URL(string: "https://spiral.md/join/OtherToken1")))

        #expect(viewModel.inviterAvatar == nil)
    }

    // MARK: - Actions

    @Test
    func installShowsTheAppClipOverlay() {
        let viewModel = makeViewModel(handOff: nil, resolver: ResolverStub())
        #expect(!viewModel.isShowingInstallOverlay)
        viewModel.install()
        #expect(viewModel.isShowingInstallOverlay)
    }

    @Test
    func thePagerStopsAtBothEnds() {
        let viewModel = makeViewModel(handOff: nil, resolver: ResolverStub())
        viewModel.showPreviousPage()
        #expect(viewModel.selectedPage == .invite)
        viewModel.showNextPage()
        viewModel.showNextPage()
        viewModel.showNextPage()
        #expect(viewModel.selectedPage == .assistant)
        viewModel.showNextPage()
        #expect(viewModel.selectedPage == .assistant)
    }

    @Test
    func everyPageHasItsCopyAndSpark() {
        for page in ClipPage.allCases {
            #expect(!page.title.isEmpty && !page.title.hasPrefix("clip."), "\(page)")
            #expect(!page.subtitle.isEmpty && !page.subtitle.hasPrefix("clip."), "\(page)")
            #expect(UIImage(named: page.imageName) != nil, "\(page)")
        }
    }

    // MARK: - Helpers

    private static let savedAt = Date(timeIntervalSince1970: 1_795_082_400)
    private static let picture = UIImage(systemName: "person.fill")
    // swiftlint:disable:next force_unwrapping
    private static let inviteURL = URL(string: "https://spiral.md/join/Qz8Hf72Kd91")!

    private func makeViewModel(handOff: ClipInviteHandOff?, resolver: ResolverStub, avatarLoader: AvatarLoaderStub = AvatarLoaderStub()) -> ClipViewModel {
        ClipViewModel(handOff: handOff, resolver: resolver, avatarLoader: avatarLoader) { Self.savedAt }
    }

    private func makeHandOff() throws -> (ClipInviteHandOff, UserDefaults) {
        let suiteName = "ClipViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (ClipInviteHandOff(defaults: defaults), defaults)
    }
}

/// Answers each request with the next queued resolution.
private final class ResolverStub: ClipInviteResolverProtocol {
    private var resolutions: [ClipInviteResolution]
    private(set) var tokens: [String] = []
    var onResolve: (() -> Void)?

    init(_ resolutions: ClipInviteResolution...) {
        self.resolutions = resolutions
    }

    func resolve(token: String) async -> ClipInviteResolution {
        tokens.append(token)
        onResolve?()
        return resolutions.isEmpty ? .offline : resolutions.removeFirst()
    }
}

/// Answers with one picture and records what it was asked for.
private final class AvatarLoaderStub: ClipAvatarLoaderProtocol {
    private let image: UIImage?
    private(set) var urls: [URL] = []
    var onLoad: (() -> Void)?

    init(image: UIImage? = nil) {
        self.image = image
    }

    func image(at url: URL) async -> UIImage? {
        urls.append(url)
        onLoad?()
        return image
    }
}
