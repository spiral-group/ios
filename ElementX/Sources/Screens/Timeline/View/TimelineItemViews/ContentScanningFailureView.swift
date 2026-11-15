//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

/// The placeholder shown in place of a media item when the content scanner wasn't able to
/// validate it. Preview and download of the content are disabled.
///
/// This view only renders the failure title and message, as a card in the bubble its message would have had.
struct ContentScanningFailureView: View {
    @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083, question 359)
    
    let failure: ContentScanningFailure
    /// One row of several, or a quote, where a card's disc would outweigh what's around it. AGENT-PLATFORM (Brief 0083, question 359)
    var isCompact = false
    
    var body: some View {
        Group {
            if isCompact {
                HStack(spacing: 8) {
                    CompoundIcon(\.error, size: .medium, relativeTo: .compound.bodyMDSemibold)
                        .foregroundStyle(.compound.iconCriticalPrimary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.compound.bodyMDSemibold)
                            .foregroundStyle(.compound.textCriticalPrimary)
                        messageText
                    }
                }
            } else {
                ChatCardRow(icon: \.error, isCritical: true, title: title) {
                    messageText
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
    
    private var messageText: some View {
        Text(message)
            .font(.compound.bodySM)
            // Compact, it sits in a critical container of its own, whatever the bubble around that.
            .foregroundStyle(isCompact ? .compound.textSecondary : ownBubbleInk?.secondaryText ?? .compound.textSecondary)
    }
    
    private var title: String {
        switch failure {
        case .notSafe: L10n.contentScannerUnsafeTitle
        case .notFound: L10n.contentScannerNotFoundTitle
        }
    }
    
    private var message: String {
        switch failure {
        case .notSafe: L10n.contentScannerUnsafeMessage
        case .notFound: L10n.contentScannerNotFound
        }
    }
}

// MARK: - Previews

struct ContentScanningFailureView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 16) {
            ContentScanningFailureView(failure: .notSafe)
            ContentScanningFailureView(failure: .notFound)
        }
        .frame(width: 260)
        .padding()
    }
}
