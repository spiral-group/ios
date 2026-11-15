//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A Spiral push is answered once. Naming a
// feed push can outlast the extension's time when a token refresh is slow; if
// iOS ends the extension first, the push would show its raw payload, a bare
// "Spiral". `expire()` answers with the generic words the builder wrote, and the
// naming that ends later is dropped.
//

import Synchronization
@preconcurrency import UserNotifications

final nonisolated class SpiralPushDelivery: Sendable {
    private struct Pending {
        let generic: UNNotificationContent
        let contentHandler: @Sendable (UNNotificationContent) -> Void
    }

    /// `nil` once the push is answered.
    private let pending: Mutex<Pending?>

    init(generic: UNNotificationContent, contentHandler: @escaping @Sendable (UNNotificationContent) -> Void) {
        pending = Mutex(Pending(generic: generic, contentHandler: contentHandler))
    }

    /// Answers with `content` unless the push was answered already.
    func deliver(_ content: UNNotificationContent) {
        guard let pending = take() else {
            MXLog.info("Spiral push: named after its time ran out; the generic words were shown")
            return
        }
        pending.contentHandler(content)
    }

    /// iOS is about to end the extension: the generic words now, unless the push was answered.
    func expire() {
        guard let pending = take() else { return }
        MXLog.info("Spiral push: time ran out, delivering the generic words")
        pending.contentHandler(pending.generic)
    }

    private func take() -> Pending? {
        pending.withLock { pending in
            defer { pending = nil }
            return pending
        }
    }
}
