//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). A notice's statement as lines, for the
// notices screen and the post's banner (lane I3): what happened at once, the
// reasons under "Why?" (decision 287).
//

import Compound
import SwiftUI

/// What happened, then "Why?" opening the reasons in full.
struct FeedNoticeStatementView: View {
    let content: FeedNoticeContent
    /// Opened at first: a notice the person is reading about on purpose (the post's banner keeps it closed).
    var isInitiallyExpanded = false

    @State private var isExpanded: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !content.summary.isEmpty {
                FeedNoticeLinesView(lines: content.summary)
            }
            if !content.reasons.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { isExpanded = !expanded }
                } label: {
                    HStack(spacing: 4) {
                        Text(UntranslatedL10n.screenFeedNoticeWhy)
                            .font(.compound.bodyMDSemibold)
                        CompoundIcon(\.chevronDown, size: .xSmall, relativeTo: .compound.bodyMDSemibold)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.compound.textActionAccent)
                    // Brief 0083: a 44 pt target.
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(Self.accessibilityValue(isExpanded: expanded))
                .accessibilityIdentifier(A11yIdentifiers.feedScreen.noticeWhy)
                if expanded {
                    FeedNoticeLinesView(lines: content.reasons)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var expanded: Bool {
        isExpanded ?? isInitiallyExpanded
    }

    /// The chevron's turn is hidden from VoiceOver, so the state is said in words.
    static func accessibilityValue(isExpanded: Bool) -> String {
        isExpanded ? UntranslatedL10n.a11yFeedExpanded : UntranslatedL10n.a11yFeedCollapsed
    }
}

struct FeedNoticeLinesView: View {
    let lines: [FeedNoticeContent.Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines, id: \.self) { line in
                switch line {
                case .text(let text):
                    Text(text)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                case .rule(let title, let explanation):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UntranslatedL10n.screenFeedNoticeRule(title))
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textPrimary)
                        if let explanation {
                            Text(explanation)
                                .font(.compound.bodyMD)
                                .foregroundStyle(.compound.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                case .moderatorComment(let comment):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UntranslatedL10n.screenFeedNoticeModeratorComment)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textPrimary)
                        // The moderator's words as written: plain text, nothing interpreted.
                        Text(verbatim: comment)
                            .font(.compound.bodyMD)
                            .foregroundStyle(.compound.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                case .appeal(let contact):
                    appeal(contact)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func appeal(_ contact: String) -> some View {
        let text = Text(UntranslatedL10n.screenFeedNoticeAppeal(contact))
            .font(.compound.bodyMD)
            .foregroundStyle(.compound.textSecondary)
        if let url = URL(string: "mailto:\(contact)"), contact.contains("@"), !contact.contains(where: \.isWhitespace) {
            Link(destination: url) { text }
                .accessibilityHint(UntranslatedL10n.a11yFeedNoticeAppealHint)
        } else {
            text
        }
    }
}

// MARK: - Previews

struct FeedNoticeStatementView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        statement(isExpanded: false)
            .previewDisplayName("Why, closed")
        statement(isExpanded: true)
            .previewDisplayName("Why, opened")
    }

    private static func statement(isExpanded: Bool) -> some View {
        FeedNoticeStatementView(content: FeedNoticeContent(notice: FeedPreviewData.notices[0]), isInitiallyExpanded: isExpanded)
            .padding(16)
    }
}
