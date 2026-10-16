//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
// Modified 2026 by the Spiral authors.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//
// AGENT-PLATFORM (Brief 0066 step 6): a draft's module, to read. Reached
// from the item menu ("Code"), as "View source" is — a secondary action
// belongs in the menu, not on the row (HIG: one primary action per object).
//

import SwiftUI

struct InteractiveDraftCode: Identifiable {
    let id = UUID()
    let title: String
    let source: String
}

struct InteractiveDraftCodeView: View {
    let code: InteractiveDraftCode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ElementNavigationStack {
            ScrollView([.vertical, .horizontal]) {
                Text(code.source)
                    .font(.compound.bodySM.monospaced())
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(code.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.actionDone) { dismiss() }
                }
            }
        }
    }
}
