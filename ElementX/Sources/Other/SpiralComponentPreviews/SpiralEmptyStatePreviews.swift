//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SwiftUI

// The previews of SpiralComponents live in the app: Sourcery reads the app's sources for
// `TestablePreview`, and Spiral's gates (`SpiralGatedPreview`) are the app's.

struct SpiralEmptyState_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        Form {
            Section {
                SpiralEmptyState(symbol: .nosign, title: UntranslatedL10n.screenAgentBlockedEmpty)
                    .listRowBackground(Color.clear)
            }
        }
        .compoundList()
        .previewDisplayName("Title only")

        Form {
            Section {
                SpiralEmptyState(symbol: .bell,
                                 title: UntranslatedL10n.screenNotificationsHubEmptyTitle,
                                 message: UntranslatedL10n.screenNotificationsHubEmptySubtitle)
                    .listRowBackground(Color.clear)
            }
        }
        .compoundList()
        .previewDisplayName("Message")

        SpiralEmptyState(symbol: .bubbleLeftAndBubbleRight,
                         title: L10n.screenRoomlistEmptyTitle,
                         message: L10n.screenRoomlistEmptyMessage,
                         action: .init(L10n.actionStartChat) { })
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .previewDisplayName("Action")

        Form {
            Section {
                ListRow(label: .plain(title: UntranslatedL10n.screenPublicProfileTitle), kind: .label)
            }
            Section {
                SpiralEmptyState(symbol: .sparkles,
                                 title: UntranslatedL10n.screenPublicProfileEmptyTitle,
                                 message: UntranslatedL10n.screenPublicProfileEmptySubtitle,
                                 size: .compact)
                    .listRowBackground(Color.clear)
            }
        }
        .compoundList()
        .previewDisplayName("Compact")

        SpiralEmptyState(symbol: .exclamationmarkCircle,
                         title: L10n.errorUnknown,
                         action: .init(L10n.actionRetry) { })
            .centredInScrollView()
            .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
            .dynamicTypeSize(.accessibility5)
            .previewDisplayName("Retry, scrolling at AX5")
    }
}
