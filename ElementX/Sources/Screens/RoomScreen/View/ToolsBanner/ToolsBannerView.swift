//
// Copyright 2025 Element Creations Ltd.
// Copyright 2024-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0044, ADR-0058): the all-participant tools
// banner. A direct sibling of `PinnedItemsBannerView` — same layout
// (indicator dots + current line + "manage" affordance, rotate on
// tap), fed by `ActiveToolsBannerState`. Visible to EVERY participant
// live (the com.spiral.tools state event syncs to all), so everyone
// sees what tools are running and can enable their own — the operator's
// marketing showcase.

import Compound
import SwiftUI

struct ToolsBannerView: View {
    let state: ActiveToolsBannerState

    /// Tap the message area — rotate to the next tool (like pins).
    let onMainButtonTap: () -> Void
    /// Tap "Manage" — open the tools panel (Your/Other sections).
    let onManageButtonTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            mainButton
            manageButton
        }
        .padding(.vertical, 16)
        .padding(.leading, 16)
        .background(Color.compound.bgCanvasDefault)
    }

    private var mainButton: some View {
        Button { onMainButtonTap() } label: {
            HStack(spacing: 10) {
                if state.count > 1 {
                    PinnedItemsIndicatorView(pinIndex: state.selectedIndex, pinsCount: state.count)
                        .accessibilityHidden(true)
                }
                CompoundIcon(state.selectedIcon, size: .small, relativeTo: .compound.bodyMD)
                    .foregroundColor(Color.compound.iconAccentPrimary)
                    .accessibilityHidden(true)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(state.isLoading || state.count <= 1)
        .accessibilityElement(children: .contain)
    }

    private var manageButton: some View {
        Button { onManageButtonTap() } label: {
            Text(UntranslatedL10n.actionManage)
                .font(.compound.bodyMDSemibold)
                .foregroundStyle(Color.compound.textActionAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
        }
        .disabled(state.isLoading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if state.count > 1 {
                Text(state.bannerIndicatorDescription)
                    .font(.compound.bodySM)
                    .foregroundColor(.compound.textActionAccent)
                    .lineLimit(1)
            }
            Text(state.displayedMessage)
                .font(.compound.bodyMD)
                .foregroundColor(.compound.textPrimary)
                .lineLimit(1)
        }
    }
}

struct ToolsBannerView_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        VStack(spacing: 20) {
            ToolsBannerView(state: .loaded(state: .init(items: [.init(id: "@a1:host#0",
                                                                      title: "Translating to English",
                                                                      icon: \.translate,
                                                                      agentMatrixUserID: "@a1:host")],
                selectedID: "@a1:host#0")),
                            onMainButtonTap: { }, onManageButtonTap: { })
                .previewDisplayName("Single tool")

            ToolsBannerView(state: .loaded(state: .init(items: [.init(id: "@a1:host#0",
                                                                      title: "Summarise calls",
                                                                      icon: \.document,
                                                                      agentMatrixUserID: "@a1:host"),
                                                        .init(id: "@a1:host#1",
                                                              title: "Record calls",
                                                              icon: \.micOn,
                                                              agentMatrixUserID: "@a1:host"),
                                                        .init(id: "@a2:host#0",
                                                              title: "Rephrase",
                                                              icon: \.translate,
                                                              agentMatrixUserID: "@a2:host")],
                                                        selectedID: "@a1:host#0")),
                            onMainButtonTap: { }, onManageButtonTap: { })
                .previewDisplayName("Multiple tools (rotates)")
        }
        .padding()
        .background(.gray)
        .previewLayout(.sizeThatFits)
    }
}
