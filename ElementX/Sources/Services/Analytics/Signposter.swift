//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import OSLog

// AGENT-PLATFORM (Brief 0078): upstream wraps Sentry performance transactions here. Spiral
// links no Sentry, so the same calls are OS signpost intervals: Instruments shows them, nothing
// is sent anywhere. Upstream's hashed homeserver tag went with Sentry.
/// A simple wrapper around `OSSignposter` for easy instrumentation
class Signposter {
    private let signposter = OSSignposter(subsystem: InfoPlistReader.main.baseBundleIdentifier, category: "Performance")
    private var transactions = [TransactionName: OSSignpostIntervalState]()

    enum TransactionName: Hashable {
        case cachedRoomList
        case upToDateRoomList
        case notificationToMessage
        case openRoom
        case sendMessage(uuid: String)

        var id: String {
            switch self {
            case .cachedRoomList:
                "Cached room list"
            case .upToDateRoomList:
                "Up-to-date room list"
            case .notificationToMessage:
                "Notification to message"
            case .openRoom:
                "Open a room"
            case .sendMessage:
                "Send a message"
            }
        }
    }

    enum SpanName: String {
        case timelineLoad = "Timeline load"
    }

    struct Span {
        fileprivate let signposter: OSSignposter
        fileprivate let state: OSSignpostIntervalState

        func finish() {
            signposter.endInterval("Span", state)
        }
    }

    // MARK: - Transactions

    func startTransaction(_ transactionName: TransactionName) {
        transactions[transactionName] = signposter.beginInterval("Transaction",
                                                                 id: signposter.makeSignpostID(),
                                                                 "\(transactionName.id, privacy: .public)")
    }

    func finishTransaction(_ transactionName: TransactionName) {
        guard let state = transactions.removeValue(forKey: transactionName) else { return }
        signposter.endInterval("Transaction", state)
    }

    // MARK: - Spans

    func addSpan(_ spanName: SpanName, toTransaction transactionName: TransactionName) -> Span? {
        guard transactions[transactionName] != nil else {
            MXLog.error("Transaction not started or already finished")
            return nil
        }

        let state = signposter.beginInterval("Span",
                                             id: signposter.makeSignpostID(),
                                             "\(spanName.rawValue, privacy: .public)")
        return Span(signposter: signposter, state: state)
    }
}
