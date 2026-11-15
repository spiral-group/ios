//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A link to one feed post:
// `https://spiral.md/feed/<id>` (universal link) and `spiral:///feed/<id>`
// (the scheme form, three slashes as `SpiralLink` writes them). The id is the
// post's UUID; there are no web pages for posts (248), so the link is
// app-only.
//

import Foundation

nonisolated struct SpiralFeedLink: Equatable, Hashable {
    /// Lower-case, as the server writes it.
    let postID: String

    private static let path = "feed"

    init?(postID: String) {
        guard let uuid = UUID(uuidString: postID) else { return nil }
        self.postID = uuid.uuidString.lowercased()
    }

    var webURL: URL {
        // A UUID and the server name always make a URL.
        // swiftlint:disable:next force_unwrapping
        URL(string: "https://\(SpiralLink.serverName)/\(Self.path)/\(postID)")!
    }

    /// Parses `https://<serverName>/feed/<uuid>` or `spiral:///feed/<uuid>`, with
    /// or without one trailing slash. A query or fragment is ignored; any other
    /// scheme, host or path is nil.
    static func parse(_ url: URL) -> SpiralFeedLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }

        switch scheme {
        case "https":
            guard url.host(percentEncoded: false)?.lowercased() == SpiralLink.serverName else { return nil }
        case "spiral":
            guard url.host(percentEncoded: false)?.isEmpty ?? true else { return nil }
        default:
            return nil
        }

        var segments = url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.first == "" else { return nil }
        segments.removeFirst()
        if segments.count == 3, segments[2].isEmpty {
            segments.removeLast()
        }

        guard segments.count == 2, segments[0] == path else { return nil }
        return SpiralFeedLink(postID: segments[1])
    }
}
