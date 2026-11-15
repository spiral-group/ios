//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

// AGENT-PLATFORM (Brief 0083): the composer's leading disc, as "+" is, with a red glyph as iOS draws a destructive
// action. It was a red-tinted glass disc with a white glyph, and on iOS 18 a red glyph without a disc.
struct VoiceMessageTrashButton: View {
    @Environment(\.isEnabled) private var isEnabled
    
    let action: () -> Void
    
    var body: some View {
        Button(role: .destructive, action: action) {
            CompoundIcon(\.delete,
                         size: Compound.supportsGlass ? .medium : .small,
                         relativeTo: .compound.headingLG)
                .foregroundStyle(isEnabled ? .compound.iconCriticalPrimary : .compound.textDisabled)
        }
        .buttonStyle(ComposerToolbarButtonStyle())
    }
}

// MARK: - Previews

struct VoiceMessageTrashButton_Previews: PreviewProvider, TestablePreview {
    static var previews: some View {
        HStack(spacing: 12) {
            VoiceMessageTrashButton { }
                .disabled(true)
            VoiceMessageTrashButton { }
        }
    }
}
