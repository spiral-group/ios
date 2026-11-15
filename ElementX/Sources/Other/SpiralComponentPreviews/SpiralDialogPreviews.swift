//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//

import Compound
import SpiralComponents
import SwiftUI

// The previews of SpiralComponents live in the app: Sourcery reads the app's sources for
// `TestablePreview`, and Spiral's gates (`SpiralGatedPreview`) are the app's.

struct SpiralDialogHeader_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        VStack(alignment: .leading, spacing: CompoundDesignTokens.space8X) {
            SpiralDialogHeader(icon: \.lockSolid,
                               title: UntranslatedL10n.screenIdentityConfirmationTitleSpiral,
                               message: UntranslatedL10n.screenIdentityConfirmationSubtitleSpiral)
            SpiralDialogHeader(icon: \.checkCircleSolid,
                               tone: .success,
                               title: UntranslatedL10n.screenSessionVerificationDeviceVerifiedSpiral)
            SpiralDialogHeader(icon: \.errorSolid,
                               tone: .critical,
                               title: UntranslatedL10n.screenEncryptionResetTitleSpiral,
                               message: UntranslatedL10n.screenEncryptionResetFooterSpiral)
        }
        .padding(CompoundDesignTokens.space6X)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Tones")
    }
}

struct SpiralCard_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview {
    static var previews: some View {
        VStack(spacing: CompoundDesignTokens.space6X) {
            SpiralCard {
                Button { } label: {
                    SpiralCardRow(icon: \.mobile, showsSeparator: true) {
                        Text(UntranslatedL10n.screenIdentityConfirmationUseAnotherDeviceSpiral)
                            .font(.compound.bodyLG)
                            .foregroundColor(.compound.textPrimary)
                    }
                }
                .buttonStyle(.spiralCardRow)

                Button { } label: {
                    SpiralCardRow(icon: \.key) {
                        Text(UntranslatedL10n.screenIdentityConfirmationUseRecoveryKeySpiral)
                            .font(.compound.bodyLG)
                            .foregroundColor(.compound.textPrimary)
                    }
                }
                .buttonStyle(.spiralCardRow)
            }

            SpiralCard {
                SpiralCardRow(icon: \.check, iconColor: .compound.iconSuccessPrimary, showsSeparator: true) {
                    Text(UntranslatedL10n.screenEncryptionResetBullet1Spiral)
                        .font(.compound.bodyLG)
                        .foregroundColor(.compound.textPrimary)
                }
                SpiralCardRow(icon: \.info, iconColor: .compound.iconSecondary) {
                    Text(UntranslatedL10n.screenEncryptionResetBullet2Spiral)
                        .font(.compound.bodyLG)
                        .foregroundColor(.compound.textPrimary)
                }
            }
        }
        .padding(CompoundDesignTokens.space4X)
        .background(Color.compound.bgCanvasDefault.ignoresSafeArea())
        .previewLayout(.sizeThatFits)
        .previewDisplayName("Rows")
    }
}
