//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: the App Clip for invite links (Brief 0086).
//

import Observation
import SwiftUI

/// What the invitation banner says.
enum ClipBannerState: Equatable {
    /// Waiting for the invocation URL or the server's answer: a placeholder of the banner's size.
    case loading
    /// A live invitation. No inviter name means a campaign token.
    case invited(inviterName: String?)
    /// Unknown, revoked, used up or expired; the token is not kept.
    case unavailable
    /// The server couldn't be asked or read; the token is kept, as it may be valid.
    case couldNotCheck(isOffline: Bool)
    /// Opened without an invite link (the default experience, or a launch from Xcode): a neutral welcome in the
    /// banner's place, which keeps its size.
    case noInvitation
}

/// The Clip's one screen: the tour pages, the invitation and the way to the full app.
@Observable
final class ClipViewModel {
    private(set) var banner: ClipBannerState = .loading
    /// The invitation being carried; nil once the server said it is dead.
    private(set) var token: String?
    var selectedPage: ClipPage = .invite
    var isShowingInstallOverlay = false
    /// The inviter on page 1's card; nil for a campaign token or without a live invitation.
    private(set) var inviterAvatar: ClipInviterAvatar?

    @ObservationIgnored private let handOff: ClipInviteHandOff?
    @ObservationIgnored private let resolver: ClipInviteResolverProtocol
    @ObservationIgnored private let avatarLoader: ClipAvatarLoaderProtocol
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var savedAt: Date?

    /// `banner`, `token` and `inviterAvatar` other than their defaults are for previews.
    init(handOff: ClipInviteHandOff?,
         resolver: ClipInviteResolverProtocol,
         avatarLoader: ClipAvatarLoaderProtocol,
         now: @escaping () -> Date = Date.init,
         banner: ClipBannerState = .loading,
         token: String? = nil,
         inviterAvatar: ClipInviterAvatar? = nil) {
        self.handOff = handOff
        self.resolver = resolver
        self.avatarLoader = avatarLoader
        self.now = now
        self.banner = banner
        self.token = token
        self.inviterAvatar = inviterAvatar
    }

    /// `spiral://join/<token>` while there is a live invitation, else the plain scheme to open the app.
    var haveSpiralURL: URL? {
        token.flatMap(ClipInviteLink.schemeURL) ?? URL(string: "spiral://")
    }

    var canRetry: Bool {
        if case .couldNotCheck = banner { token != nil } else { false }
    }

    // MARK: - Invocation

    /// The URL the Clip was invoked with. The invitation is written to the App Group at once, before the
    /// server answers, so an install started meanwhile still carries it.
    func open(_ url: URL) async {
        guard let token = ClipInviteLink.token(from: url) else {
            if token == nil, banner == .loading {
                banner = .noInvitation
            }
            return
        }
        guard token != self.token else {
            await retry() // The same link again only asks again after a failed check.
            return
        }

        self.token = token
        let savedAt = now()
        self.savedAt = savedAt
        handOff?.write(ClipInvite(token: token, savedAt: savedAt))
        await check()
    }

    /// No invocation URL arrived (a launch from Xcode or the App Library without one).
    func invocationTimedOut() {
        if token == nil, banner == .loading {
            banner = .noInvitation
        }
    }

    func retry() async {
        guard canRetry else { return }
        await check()
    }

    func install() {
        isShowingInstallOverlay = true
    }

    // MARK: - Pages

    func showNextPage() {
        selectedPage = selectedPage.next ?? selectedPage
    }

    func showPreviousPage() {
        selectedPage = selectedPage.previous ?? selectedPage
    }

    // MARK: - Private

    private func check() async {
        guard let token, let savedAt else { return }
        banner = .loading

        let resolution = await resolver.resolve(token: token)
        guard self.token == token else { return } // Another link arrived meanwhile.

        switch resolution {
        case .valid(let inviterDisplayName, let inviterUserID, let inviterAvatarURL):
            let name = inviterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let inviterName = name?.isEmpty == false ? name : nil
            handOff?.write(ClipInvite(token: token, inviterDisplayName: inviterName, inviterUserID: inviterUserID, savedAt: savedAt))
            banner = .invited(inviterName: inviterName)
            inviterAvatar = inviterName.map { ClipInviterAvatar(name: $0) }
            if inviterName != nil, let inviterAvatarURL {
                await loadAvatar(inviterAvatarURL, token: token)
            }
        case .unavailable:
            handOff?.clear()
            self.token = nil
            self.savedAt = nil
            inviterAvatar = nil
            banner = .unavailable
        case .offline:
            banner = .couldNotCheck(isOffline: true)
        case .unreadable:
            banner = .couldNotCheck(isOffline: false)
        }
    }
    
    /// The monogram shows until the picture is in; a picture that doesn't load leaves the monogram.
    private func loadAvatar(_ url: URL, token: String) async {
        guard let image = await avatarLoader.image(at: url), self.token == token else { return }
        inviterAvatar?.image = image
    }
}

/// The inviter on page 1's invitation card: their picture, or their initial until it loads or when they have none.
struct ClipInviterAvatar: Equatable {
    let name: String
    let initial: String
    var image: UIImage?
    
    init(name: String, image: UIImage? = nil) {
        self.name = name
        // As the app's `PlaceholderAvatarImage`: the first character of the name, upper-cased.
        initial = name.first?.uppercased() ?? ""
        self.image = image
    }
}
