//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0063): one person card of `05 · Group call`.

import Compound
import SwiftUI

/// `C/Participant` (`05 · Group call`): a white person card — avatar, name,
/// a quiet state line, and the honest right-side marks: translated, the
/// speaking mini-wave, muted.
struct NativeCallParticipantRow: View {
    let participant: NativeCallParticipant
    let profile: NativeCallMemberProfile?
    /// The language of this speaker's live simultaneous lane, for
    /// `Covered in English`.
    var coveredLanguage: String?
    let mediaProvider: MediaProviderProtocol?

    var body: some View {
        HStack(spacing: 12) {
            NativeCallLetterAvatar(userID: participant.userID,
                                   profile: profile,
                                   fallbackName: NativeCallFallbackName.make(mxid: participant.userID),
                                   size: 40,
                                   mediaProvider: mediaProvider)
                // `05` rings the speaking person's avatar in the accent.
                .overlay {
                    if participant.isSpeaking {
                        Circle()
                            .strokeBorder(Color.compound.iconAccentPrimary, lineWidth: 2)
                            .padding(-3)
                    }
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let stateText {
                    Text(stateText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if participant.isTranslated {
                // B4: this raw voice is replaced by the speaker's live
                // simultaneous lane right now.
                Image(systemName: "globe")
                    .font(.footnote)
                    .foregroundStyle(.compound.iconAccentPrimary)
                    .accessibilityLabel(UntranslatedL10n.screenNativeCallParticipantTranslated)
            }

            if participant.isSpeaking {
                // The wave hides its own bars from VoiceOver, so a plain
                // label on it would attach to nothing —
                // `accessibilityElement()` makes the wrapper one element that
                // CAN carry the word the visible line used to. Same intent as
                // the muted glyph below, one extra step because this view is
                // decorative all the way down.
                NativeCallVoiceWave(userID: participant.userID, scale: .row)
                    .accessibilityElement()
                    .accessibilityLabel(UntranslatedL10n.a11yNativeCallParticipantSpeaking)
            }

            if !participant.isAudioEnabled, !participant.isOnHold {
                Image(systemName: "mic.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityLabel(UntranslatedL10n.a11yNativeCallParticipantMuted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var displayName: String {
        // The screen's own invariant is "people, never raw MXIDs"
        // (audit A6-5): profiles arrive async, and until they do the
        // roster showed `@user:server` — the shared fallback renders the
        // localpart as a name instead, same as everywhere else.
        profile?.displayName ?? NativeCallFallbackName.make(mxid: participant.userID)
    }

    /// `05`'s quiet state line, most specific fact first: the media path,
    /// then the translation covering this voice, then mute.
    ///
    /// Speaking is deliberately NOT here. It already has two loud visuals —
    /// the accent ring around the avatar and the animated wave — and a word
    /// that appears and vanishes with every syllable is noise next to them.
    /// The fact is not lost: it moved to the wave's accessibility label,
    /// because the ring and the wave are decorative to VoiceOver and the
    /// text was the only thing carrying it.
    private var stateText: String? {
        switch participant.mediaState {
        case .connecting: return UntranslatedL10n.screenNativeCallParticipantConnecting
        case .waitingForKeys: return UntranslatedL10n.screenNativeCallParticipantWaitingForKeys
        case .connected: break
        }
        // Brief 0068: a hold outranks the muted glyph — the microphone IS
        // muted underneath, but "On hold" is the fact.
        if participant.isOnHold {
            return UntranslatedL10n.screenNativeCallStatusOnHold
        }
        if participant.isReconnecting {
            return UntranslatedL10n.screenNativeCallParticipantReconnecting
        }
        if participant.isTranslated, let coveredLanguage {
            return UntranslatedL10n.screenNativeCallParticipantCovered(coveredLanguage)
        }
        if !participant.isAudioEnabled {
            return UntranslatedL10n.screenNativeCallParticipantMuted
        }
        return nil
    }
}
