//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: post catalogue links (decision 111, App Review 4.7.4).
//
// `https://spiral.md/catalog/<id>` is a template's public page and its
// universal link; `spiral:///catalog/<id>` is that page's "Open in Spiral"
// button (universal links do not fire on same-domain taps in Safari —
// Apple TN3155). Three slashes, as `SpiralLink` writes its scheme URLs.
// The index (`/catalog/`) and the catalogue's files (`/catalog/index.json`,
// `/catalog/<id>/app.jsx`) are not links: the AASA leaves them out, and so
// does this parser. The id grammar is the one the pages and the AASA use
// (docs/DESIGNS/post-catalogue-links-2026-10-12.md § 2).
//

import Foundation

/// A link to one template of the post catalogue.
nonisolated struct SpiralCatalogLink: Equatable, Hashable {
    let templateID: String

    private static let path = "catalog"
    private static let maxLength = 64

    init?(templateID: String) {
        guard Self.validTemplateID(templateID) else { return nil }
        self.templateID = templateID
    }

    /// The template's public page (universal link).
    var webURL: URL {
        URL(string: "https://\(SpiralLink.serverName)/\(Self.path)/\(templateID)")!
    }

    /// The custom-scheme URL the page's open button uses.
    var schemeURL: URL {
        URL(string: "spiral:///\(Self.path)/\(templateID)")!
    }

    // MARK: - Parsing

    /// Parses `https://<serverName>/catalog/<id>` or `spiral:///catalog/<id>`,
    /// with or without one trailing slash. A query or fragment is ignored;
    /// any other scheme, host or path is nil.
    static func parse(_ url: URL) -> SpiralCatalogLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }

        switch scheme {
        case "https":
            guard url.host(percentEncoded: false)?.lowercased() == SpiralLink.serverName else { return nil }
        case "spiral":
            // `spiral://catalog/poll` would make `catalog` the host; the
            // pages write the empty-host form, as `SpiralLink` does.
            guard url.host(percentEncoded: false)?.isEmpty ?? true else { return nil }
        default:
            return nil
        }

        // Split by hand, keeping empty segments, so `/catalog//poll` and
        // `/catalog/poll//` are refused rather than read as `/catalog/poll`.
        var segments = url.path(percentEncoded: false).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.first == "" else { return nil }
        segments.removeFirst()
        if segments.count == 3, segments[2].isEmpty {
            segments.removeLast()
        }

        guard segments.count == 2, segments[0] == path else { return nil }
        return SpiralCatalogLink(templateID: segments[1])
    }

    // MARK: - Validation

    /// `^[a-z0-9]+(-[a-z0-9]+)*$`, at most 64 characters.
    static func validTemplateID(_ value: String) -> Bool {
        guard (1...maxLength).contains(value.count),
              value.first != "-", value.last != "-",
              !value.contains("--") else {
            return false
        }
        return value.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "-")
        }
    }
}
