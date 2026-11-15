//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: feed (Brief 0082). The feed rules as one friendly card
// (decision 287), shown when the server answers a post or comment with `409
// feed-rules-not-accepted`. Its one button agrees and sends the same text with
// the same key; closing it sends nothing. The rules themselves are unchanged
// (`FeedRules.version`): a draft for lane L (legal text, the operator's
// sign-off) with the contact point (DSA Art. 11–12).
//

import Compound
import SwiftUI

struct FeedRulesSheet: View {
    let isAccepting: Bool
    let acceptFailed: Bool
    let accept: () -> Void
    let decline: () -> Void
    /// "Got it, post", or "Got it, comment" under a post (lane I3).
    var agreeTitle = UntranslatedL10n.screenFeedRulesAgree

    private static let rules: [(icon: KeyPath<CompoundIcons, Image>, text: String)] = [
        (\.reaction, UntranslatedL10n.screenFeedRulesKind),
        (\.block, UntranslatedL10n.screenFeedRulesNoHarm),
        (\.lock, UntranslatedL10n.screenFeedRulesPrivacy),
        (\.link, UntranslatedL10n.screenFeedRulesNoScams),
        (\.image, UntranslatedL10n.screenFeedRulesOwnContent)
    ]

    var body: some View {
        ElementNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(UntranslatedL10n.screenFeedRulesIntro)
                        .font(.compound.bodyLG)
                        .foregroundStyle(.compound.textPrimary)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Self.rules.indices, id: \.self) { index in
                            rule(Self.rules[index].icon, Self.rules[index].text)
                        }
                    }

                    Text(UntranslatedL10n.screenFeedRulesModeration)
                        .font(.compound.bodyMD)
                        .foregroundStyle(.compound.textSecondary)
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) { buttons }
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .navigationTitle(UntranslatedL10n.screenFeedRulesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: decline) {
                        CompoundIcon(\.close)
                            .accessibilityLabel(L10n.actionClose)
                    }
                    .disabled(isAccepting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isAccepting)
    }

    private func rule(_ icon: KeyPath<CompoundIcons, Image>, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CompoundIcon(icon, size: .small, relativeTo: .compound.bodyMD)
                .foregroundStyle(.compound.iconSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.compound.bodyLG)
                .foregroundStyle(.compound.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if acceptFailed {
                Text(UntranslatedL10n.screenFeedRulesAcceptFailed)
                    .font(.compound.bodySM)
                    .foregroundStyle(.compound.textCriticalPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.rulesAcceptFailed)
            }
            Button(action: accept) {
                if isAccepting {
                    ProgressView()
                        .accessibilityLabel(UntranslatedL10n.screenFeedComposerPosting)
                } else {
                    Text(agreeTitle)
                }
            }
            .buttonStyle(.compound(.primary))
            .disabled(isAccepting)
            .accessibilityIdentifier(A11yIdentifiers.feedComposerScreen.rulesAgree)
        }
        .padding(16)
        .background(.compound.bgCanvasDefault)
    }
}

// MARK: - Previews

struct FeedRulesSheet_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        FeedRulesSheet(isAccepting: false, acceptFailed: false, accept: { }, decline: { })
            .previewDisplayName("Rules")
        FeedRulesSheet(isAccepting: true, acceptFailed: false, accept: { }, decline: { })
            .previewDisplayName("Accepting")
        FeedRulesSheet(isAccepting: false, acceptFailed: true, accept: { }, decline: { })
            .previewDisplayName("Accept failed")
        FeedRulesSheet(isAccepting: false, acceptFailed: false, accept: { }, decline: { })
            .dynamicTypeSize(.accessibility5)
            .previewDisplayName("AX5")
    }
}
