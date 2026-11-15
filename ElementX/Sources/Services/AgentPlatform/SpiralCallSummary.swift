//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 371): a call's summary as a card. It reaches the app as a notice does, a `com.spiral.notice`
// of the kind `call_summary`, as the SDK hands over the extra keys of no `m.text`. Unlike a notice it is what the agent
// said, in the agent's words and language, so it stays a message: reactions, a reply, forwarding and copying.
//

import Foundation

nonisolated struct SpiralCallSummary: Hashable {
    private enum Fold {
        /// More than the card's folded lines hold at the default text size, so a fold always hides something there.
        static let textLength = 300
        static let itemCount = 3
    }
    
    /// Nil on a summary stored without titles: the app words it.
    let title: String?
    let text: String
    /// Nil on a summary stored without titles: the list then goes without one.
    let decisionsTitle: String?
    let decisions: [String]
    /// Nil on a summary stored without titles: the list then goes without one.
    let actionItemsTitle: String?
    let actionItems: [String]
    /// Worked out here and not in the row, which measures nothing as it scrolls.
    let isLong: Bool
    
    init(title: String? = nil,
         text: String,
         decisionsTitle: String? = nil,
         decisions: [String] = [],
         actionItemsTitle: String? = nil,
         actionItems: [String] = []) {
        self.title = title
        self.text = text
        self.decisionsTitle = decisionsTitle
        self.decisions = decisions
        self.actionItemsTitle = actionItemsTitle
        self.actionItems = actionItems
        isLong = text.count > Fold.textLength
            || decisions.count > Fold.itemCount
            || actionItems.count > Fold.itemCount
            || (decisions + actionItems).map(\.count).reduce(0, +) > Fold.textLength
    }
    
    var displayTitle: String {
        title ?? UntranslatedL10n.noticeSummaryMovedTitle
    }
    
    /// All the card says, for VoiceOver, whatever a fold hides.
    var accessibilityText: String {
        ([displayTitle, text, decisions.isEmpty ? nil : decisionsTitle] + decisions + [actionItems.isEmpty ? nil : actionItemsTitle] + actionItems)
            .compactMap(\.self)
            .joined(separator: "\n")
    }
    
    /// Parses the SDK's `data` JSON for a `com.spiral.notice` message. Nil for any other message or a summary of a shape
    /// this build doesn't know: the caller then shows `body`.
    init?(msgtype: String, data: String) {
        guard msgtype == SpiralNotice.msgtype,
              let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let facts = object[SpiralNotice.key] as? [String: Any],
              facts["kind"] as? String == "call_summary",
              let text = Self.nonBlank(facts["summary"]),
              let decisions = facts["decisions"] as? [String],
              let actionItems = facts["action_items"] as? [String] else {
            return nil
        }
        
        self.init(title: Self.nonBlank(facts["title"]),
                  text: text,
                  decisionsTitle: Self.nonBlank(facts["decisions_title"]),
                  decisions: decisions.compactMap(Self.nonBlank),
                  actionItemsTitle: Self.nonBlank(facts["action_items_title"]),
                  actionItems: actionItems.compactMap(Self.nonBlank))
    }
    
    private static func nonBlank(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
