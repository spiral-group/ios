//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A feed engagement push carries ids only
// (decision 266); the NSE reads the activity entry it names with the
// session's access token to say who and what: "Taras: so true", "Taras and 2
// others liked your post" (lane I5). An access token lives minutes, so the one
// in the keychain is often stale when a push wakes an idle phone: a `401` asks
// `refreshAccessToken` for a newer one and reads once more. The reads end by
// the push's deadline; a refresh starts only with time left for it and is never
// cut short (`FeedPushBudget`). Any other failure — no single session, no
// fresh token, the entry not on the newest page, a sensitive entry — leaves the
// generic words in place. Nothing is stored and the logs carry no names or
// text. Target-portable (pulled into the NSE), so it stays on Foundation and
// the shared strings.
//

import Foundation
import UserNotifications

nonisolated struct FeedPushActivityReader {
    /// The newest entries are read: a push's entry was just made, so it is among them.
    static let pageSize = 50
    /// One session for every push the process handles, not one per push.
    static let sharedSession = makeSession()

    let baseURL: URL
    let accessToken: String
    var budget = FeedPushBudget(start: .now)
    /// A token newer than the rejected one, or `nil` when there is none.
    let refreshAccessToken: @Sendable (_ rejected: String) async -> String?
    var urlSession = Self.sharedSession

    /// The engagement push words for `subject`, or `nil` to keep the generic ones.
    func words(for subject: SpiralPushContentBuilder.Subject) async -> Words? {
        guard let entryID = Self.entryID(for: subject) else { return nil }

        var result = await readPage(with: accessToken)
        if case .unauthorized = result {
            // Not under the deadline: a refresh cut short mid-exchange could leave the keychain with a revoked pair.
            guard budget.allowsRefresh else {
                MXLog.info("Feed push: too little time left to refresh the token")
                return nil
            }
            guard let refreshed = await refreshAccessToken(accessToken) else {
                MXLog.info("Feed push: no fresh token after a 401")
                return nil
            }
            result = await readPage(with: refreshed)
        }
        guard case .page(let page) = result else { return nil }

        guard let entry = page.items.first(where: { $0.id == entryID }) else {
            MXLog.info("Feed push: \(entryID) is not among the newest activity")
            return nil
        }
        return Self.words(for: entry)
    }

    private enum ReadResult {
        case page(Page)
        case unauthorized
        case failed
    }

    /// The read ends by the push's deadline; past it there is no read at all.
    private func readPage(with token: String) async -> ReadResult {
        let remaining = budget.remaining
        guard remaining > .zero else {
            MXLog.info("Feed push: no time left to read the activity")
            return .failed
        }
        return await withTaskGroup(of: ReadResult?.self) { group in
            group.addTask { await fetchPage(with: token) }
            group.addTask {
                try? await Task.sleep(for: remaining)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            guard let first else {
                MXLog.info("Feed push: the activity read ran out of time")
                return .failed
            }
            return first
        }
    }

    private func fetchPage(with token: String) async -> ReadResult {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/feed/activity"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(Self.pageSize))]
        guard let url = components?.url else { return .failed }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200:
                return try .page(JSONDecoder().decode(Page.self, from: data))
            case 401:
                MXLog.info("Feed push: the activity read answered 401")
                return .unauthorized
            default:
                MXLog.info("Feed push: the activity read answered \(status)")
                return .failed
            }
        } catch {
            // Cancelled when the deadline won the race, which `readPage` has logged already.
            if !Task.isCancelled {
                MXLog.info("Feed push: the activity read failed: \(type(of: error))")
            }
            return .failed
        }
    }

    /// The push's activity entry: `like:<post>:<day>`, `comment:<id>`, `reply:<id>`.
    static func entryID(for subject: SpiralPushContentBuilder.Subject) -> String? {
        switch subject.kind {
        case "feed_like":
            subject.group.map { "like:\(subject.id):\($0)" }
        case "feed_comment":
            "comment:\(subject.id)"
        case "feed_reply":
            "reply:\(subject.id)"
        default:
            nil
        }
    }

    struct Words: Equatable {
        let body: String
        let subtitle: String?
    }

    /// A sensitive entry's text stays out of the banner: the generic words show instead.
    static func words(for entry: Entry) -> Words? {
        guard !entry.sensitive, let actor = entry.actors.first else { return nil }
        let name = FeedActivityText.name(userID: actor.mxid, name: actor.name, isNameWithheld: actor.nameWithheld ?? false)
        switch entry.kind {
        case "like":
            return Words(body: FeedActivityText.likes(name: name, others: max(0, entry.total - 1)), subtitle: nil)
        case "comment", "reply":
            guard let preview = entry.preview, !preview.isEmpty else { return nil }
            return Words(body: FeedActivityText.quote(name: name, text: preview), subtitle: FeedActivityText.context(isReply: entry.kind == "reply"))
        default:
            return nil
        }
    }

    /// The push's content with the words in it; the generic content when there are none.
    static func applying(_ words: Words?, to content: UNNotificationContent) -> UNNotificationContent {
        guard let words, let mutable = content.mutableCopy() as? UNMutableNotificationContent else { return content }
        mutable.body = words.body
        if let subtitle = words.subtitle {
            mutable.subtitle = subtitle
        }
        return mutable
    }

    /// No copy of the answer is kept, and a slow server leaves the generic words well before the NSE's deadline.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        return URLSession(configuration: configuration)
    }

    // MARK: - The wire (only what the words need)

    struct Page: Decodable {
        let items: [Entry]
    }

    struct Entry: Decodable {
        let id: String
        let kind: String
        let actors: [Actor]
        let total: Int
        let preview: String?
        let sensitive: Bool
    }

    struct Actor: Decodable {
        let mxid: String
        let name: String?
        let nameWithheld: Bool?

        enum CodingKeys: String, CodingKey {
            case mxid
            case name
            case nameWithheld = "name_withheld"
        }
    }
}

/// A feed push's time, from when iOS handed it over. The platform reads end
/// within `readDeadline`, well inside the ~30 s iOS gives the extension. A token
/// refresh starts only while `refreshNeeds` of it remain and then runs to its
/// end, bounded by the SDK client's own request timeouts, so the push is never
/// answered while a refresh token is mid-exchange.
nonisolated struct FeedPushBudget {
    static let readDeadline: Duration = .seconds(20)
    static let refreshNeeds: Duration = .seconds(12)

    let start: ContinuousClock.Instant
    var now: @Sendable () -> ContinuousClock.Instant = { .now }

    var remaining: Duration {
        max(.zero, now().duration(to: start.advanced(by: Self.readDeadline)))
    }

    var allowsRefresh: Bool {
        remaining >= Self.refreshNeeds
    }
}
