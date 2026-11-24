//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0085, operator remark 403 L8): the Assistants sheet's resting height hugs its root page instead
// of half the screen, so the call above it — the other person's name — stays in view. The height is the root laid out
// in its resting state (the header, the four buttons, Translation's question and Start — 1.0.3, the call lab's pick C,
// lowered at the operator's word), measured once per text size on the call screen before the sheet opens; a job's
// question with Cancel, or a card in the buttons' place, scrolls if it is ever taller. It never follows the live content, so the sheet doesn't move when a row comes or goes
// (no jumps); a root with less content leaves a gap.
// Pushed pages keep it, and `.large` stays for the pull. At accessibility sizes it is never taller than `.medium`.

import Compound
import SpiralTokens
import SwiftUI
import Synchronization

/// The resting detent: the measured root; at accessibility sizes never taller than half the sheet's maximum.
struct NativeCallAssistantsDetent: CustomPresentationDetent {
    /// Measured heights per text size: the sheet's own content plus the bottom safe area.
    private static let heights = Mutex<[DynamicTypeSize: CGFloat]>([:])

    static func height(in context: Context) -> CGFloat? {
        resting(measured: heights.withLock { $0[context.dynamicTypeSize] },
                maximum: context.maxDetentValue,
                isAccessibilitySize: context.dynamicTypeSize.isAccessibilitySize)
    }

    /// The measured root; half the maximum (about `.medium`) until it is measured, and at accessibility sizes whenever
    /// the root wouldn't fit in it, so the call stays in view.
    static func resting(measured: CGFloat?, maximum: CGFloat, isAccessibilitySize: Bool) -> CGFloat {
        let medium = maximum / 2
        guard let measured else { return medium }
        return min(measured, isAccessibilitySize ? medium : maximum)
    }

    static func store(_ height: CGFloat, for size: DynamicTypeSize) {
        heights.withLock { $0[size] = height }
    }

    static func measured(for size: DynamicTypeSize) -> CGFloat? {
        heights.withLock { $0[size] }
    }
}

extension PresentationDetent {
    static let nativeCallAssistants = PresentationDetent.custom(NativeCallAssistantsDetent.self)
}

/// The root's tallest common layout, drawn hidden on the call screen at its width: what the detent measures. It takes no
/// state of the call, so the height can't follow the content.
struct NativeCallAssistantsDetentMeasurer: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = proxy.safeAreaInsets.bottom
            page { rows }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: proxy.size.width)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                NativeCallAssistantsDetent.store(height + bottomInset, for: dynamicTypeSize)
            }
        }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// `NativeCallSheetPage`'s frame, without its scroll view.
    private func page(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) {
            NativeCallSheetHeader(title: UntranslatedL10n.screenNativeCallAssistantsYourAssistant,
                                  status: UntranslatedL10n.screenNativeCallAssistantsStatusStandby,
                                  onClose: { }) {
                Circle().frame(width: SpiralAvatarSize.small, height: SpiralAvatarSize.small)
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.top, CompoundDesignTokens.space5X)
            .padding(.bottom, CompoundDesignTokens.space3X)
            VStack(spacing: CompoundDesignTokens.space3X) {
                content()
            }
            .padding(.horizontal, CompoundDesignTokens.space4X)
            .padding(.bottom, CompoundDesignTokens.space6X)
        }
    }

    /// The four buttons, Translation's question (its cost line under the title, the language beside it) and Start.
    @ViewBuilder
    private var rows: some View {
        NativeCallAssistantDockView(state: NativeCallAssistantDockState(.init()), isInteractive: false) { _ in }
        NativeCallSheetRow(icon: "translate",
                           title: UntranslatedL10n.screenNativeCallAssistantsTranslateQuestionTitle,
                           detail: UntranslatedL10n.screenNativeCallAssistantsStartTranslationDetail,
                           value: NativeCallTranslationCopy.languageTitle("uk"),
                           showsChevron: true)
        NativeCallSheetPrimaryButton(title: UntranslatedL10n.screenNativeCallAssistantsStartTranslation) { }
    }
}
