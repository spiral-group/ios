//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SpiralTokens
import SwiftUI

struct SpiralPreloader_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        Form {
            Section {
                ListRow(kind: .custom {
                    SpiralPreloader(label: L10n.commonLoading) {
                        SpiralPlaceholderRows(count: 4, leading: .icon)
                    }
                })
            }
        }
        .compoundList()
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Rows")

        ScrollView {
            SpiralPreloader(label: L10n.commonLoading) {
                SpiralPlaceholderRows(count: 6, leading: .avatar(SpiralAvatarSize.medium))
            }
        }
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Avatars")

        Form {
            Section {
                ListRow(kind: .custom {
                    SpiralPreloader(label: L10n.commonLoading) {
                        SpiralPlaceholderLines(count: 4)
                            .padding(CompoundDesignTokens.space4X)
                    }
                })
            }
        }
        .compoundList()
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Lines")

        // One late value in its own slot: the row below is the same row, loaded.
        Form {
            Section {
                ListRow(label: .default(title: L10n.commonLoading, icon: \.user),
                        details: .icon(Text(verbatim: "00000000").spiralLoadingSlot(true, label: L10n.commonLoading)),
                        kind: .label)
                ListRow(label: .default(title: L10n.commonLoading, icon: \.user),
                        details: .icon(Text(verbatim: "00000000").spiralLoadingSlot(false, label: L10n.commonLoading)),
                        kind: .label)
            }
        }
        .compoundList()
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Slot")

        // A setting not known yet: the capsule stands where the row below has its switch.
        Form {
            Section {
                ListRow(kind: .custom {
                    HStack(spacing: 0) {
                        ListRowLabel<EmptyView>.plain(title: L10n.commonLoading, description: L10n.commonLoading)
                        Spacer()
                        SpiralPreloader(label: L10n.commonLoading) {
                            SpiralPlaceholderToggle()
                        }
                    }
                    .padding(.trailing, ListRowPadding.horizontal)
                })
                ListRow(label: .plain(title: L10n.commonLoading, description: L10n.commonLoading),
                        kind: .toggle(.constant(true)))
            }
        }
        .compoundList()
        .environment(\.spiralPreloaderDelay, .zero)
        .previewDisplayName("Toggle")

        // What every load shows for its first 250 ms: the list, with nothing in it yet.
        Form {
            Section {
                ListRow(kind: .custom {
                    SpiralPreloader(label: L10n.commonLoading) {
                        SpiralPlaceholderRows(count: 4, leading: .icon)
                    }
                })
            }
        }
        .compoundList()
        .previewDisplayName("Before the delay")
    }
}
