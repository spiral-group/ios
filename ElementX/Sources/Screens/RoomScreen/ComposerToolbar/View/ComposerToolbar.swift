//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Combine
import Compound
import MatrixRustSDK
import SwiftUI
import WysiwygComposer

struct ComposerToolbar: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    @ObservedObject var context: ComposerToolbarViewModel.Context
    
    @FocusState private var composerFocused: Bool
    
    /// - When Liquid Glass is available, the buttons and composer are all 44pt x 44pt.
    /// - On iOS 18 and below, the main buttons are 36pt x 36pt and the composer is 40pt high, so some
    ///   additional padding is required to centre the buttons vertically when there's a single line of text,
    ///   but preserve their position (using bottom alignment) when there's 2 or more lines of text.
    private var buttonVerticalPadding: CGFloat {
        Compound.supportsGlass ? 0 : 2 // AGENT-PLATFORM (Brief 0083): 36pt discs beside Spiral's 40pt field
    }
    
    var body: some View {
        VStack(spacing: 8) {
            topBar
            
            if context.composerFormattingEnabled {
                if verticalSizeClass != .compact,
                   context.composerExpanded {
                    suggestionView
                        .padding(.leading, -5)
                        .padding(.trailing, -8)
                }
                bottomBar
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.bottom, context.composerFormattingEnabled ? 8 : 12)
        // AGENT-PLATFORM (Brief 0083): no outline around the composer while it formats; the field and the
        // formatting row sit on the bar as the plain composer does.
        .safeAreaInset(edge: .top) {
            if !context.viewState.isRoomEncrypted {
                Label {
                    Text(L10n.commonNotEncrypted)
                        .font(.compound.bodySM)
                        .foregroundStyle(.compound.textSecondary)
                } icon: {
                    CompoundIcon(\.lockOff, size: .xSmall, relativeTo: .compound.bodyMD)
                        .foregroundStyle(.compound.iconInfoPrimary)
                }
                .padding(4.0)
            }
        }
        .disabled(!context.viewState.canSend)
        .alert(item: $context.alertInfo)
    }
    
    /// AGENT-PLATFORM (Brief 0083, question 357): the suggestions outside an expanded composer, for the screen to float
    /// above the composer's bar (`timelineComposerBar`). A system bar takes no touch outside its own bounds.
    var floatingSuggestions: some View {
        FloatingSuggestions(context: context)
    }
    
    private var suggestionView: some View {
        CompletionSuggestionView(mediaProvider: context.mediaProvider,
                                 items: context.viewState.suggestions,
                                 showBackgroundShadow: false) { suggestion in
            context.send(viewAction: .selectedSuggestion(suggestion))
        }
    }
    
    // AGENT-PLATFORM (Brief 0083): the trailing button moved inside the field (`fieldAction` and the voice
    // message composers' own actions), as Messages draws send and the microphone.
    private var topBar: some View {
        mainTopBarContent
            .animation(.linear(duration: 0.15), value: context.viewState.composerMode)
    }
    
    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 4) {
            closeRTEButton
            
            FormattingToolbar(formatItems: context.formatItems) { action in
                context.send(viewAction: .composerAction(action: action.composerAction))
            }
            .padding(.horizontal, 5)
            
            sendButton
        }
    }
    
    private var topBarLayout: some Layout {
        HStackLayout(alignment: .bottom, spacing: 12)
    }
    
    private var mainTopBarContent: some View {
        ZStack(alignment: .bottom) {
            topBarLayout {
                if !context.composerFormattingEnabled {
                    RoomAttachmentPicker(context: context)
                        .scaledPadding(.vertical, buttonVerticalPadding, relativeTo: .compound.headingLG)
                }
                messageComposer
            }
            .opacity(context.viewState.isVoiceMessageModeActivated ? 0 : 1)
            .accessibilityHidden(context.viewState.isVoiceMessageModeActivated)
            
            if context.viewState.isVoiceMessageModeActivated {
                voiceMessageContent
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var closeRTEButton: some View {
        Button {
            context.composerFormattingEnabled = false
            context.composerExpanded = false
        } label: {
            CompoundIcon(\.close,
                         size: Compound.supportsGlass ? .medium : .small,
                         relativeTo: .compound.headingLG)
        }
        .buttonStyle(ComposerToolbarButtonStyle())
        .accessibilityLabel(L10n.richTextEditorCloseFormattingOptions)
        .accessibilityIdentifier(A11yIdentifiers.roomScreen.composerToolbar.closeFormattingOptions)
    }
    
    private var sendButton: some View {
        SendButton(mode: context.viewState.sendButtonMode, action: sendMessage)
            .accessibilityLabel(context.viewState.sendButtonAccessibilityLabel)
            .disabled(context.viewState.sendButtonDisabled)
            .animation(.linear(duration: 0.1).disabledDuringTests(), value: context.viewState.sendButtonDisabled)
            .keyboardShortcut(.return, modifiers: [.command])
            .accessibilityIdentifier(A11yIdentifiers.roomScreen.sendButton)
    }
    
    private var messageComposer: some View {
        MessageComposer(plainComposerText: $context.plainComposerText,
                        presendCallback: $context.presendCallback,
                        selectedRange: $context.selectedRange,
                        composerView: composerView,
                        mode: context.viewState.composerMode,
                        placeholder: placeholder,
                        composerFormattingEnabled: context.composerFormattingEnabled,
                        showResizeGrabber: context.composerFormattingEnabled,
                        isExpanded: $context.composerExpanded,
                        trailing: fieldAction) { // AGENT-PLATFORM (Brief 0083)
            sendMessage()
        } editAction: {
            context.send(viewAction: .editLastMessage)
        } pasteAction: { providers in
            context.send(viewAction: .handlePasteOrDrop(providers: providers))
        } cancellationAction: {
            switch context.viewState.composerMode {
            case .edit:
                context.send(viewAction: .cancelEdit)
            case .reply:
                context.send(viewAction: .cancelReply)
            default:
                break
            }
        } onAppearAction: {
            context.send(viewAction: .composerAppeared)
        }
        .onDisappear {
            context.send(viewAction: .composerDisappeared)
        }
        .environmentObject(context)
        .focused($composerFocused)
        // AGENT-PLATFORM (Brief 0083): the identifier sits on the text field inside `MessageComposer`; here it covered
        // the send button that now sits in the field's trailing end, and UI tests found no `room-send_button`.
        .onTapGesture {
            guard !composerFocused else { return }
            composerFocused = true
        }
        .onChange(of: context.composerFocused) { _, newValue in
            guard composerFocused != newValue else { return }
            
            composerFocused = newValue
        }
        .onChange(of: composerFocused) { _, newValue in
            context.composerFocused = newValue
        }
        .onChange(of: context.plainComposerText) {
            context.send(viewAction: .plainComposerTextChanged)
        }
        .onChange(of: context.composerFormattingEnabled) {
            context.send(viewAction: .didToggleFormattingOptions)
        }
        .onChange(of: context.selectedRange) {
            context.send(viewAction: .selectedTextChanged)
        }
        .onAppear {
            composerFocused = context.composerFocused
        }
    }
    
    // AGENT-PLATFORM (Brief 0083): the text field's action. While formatting, send is on the formatting row; a voice
    // message's composers carry their own (the field stays underneath, hidden, to keep the keyboard). Without an
    // action, a sliver keeps the text off the field's end as far as the leading side's.
    @ViewBuilder
    private var fieldAction: some View {
        if context.composerFormattingEnabled || context.viewState.isVoiceMessageModeActivated {
            Color.clear
                .frame(width: CompoundDesignTokens.space1X, height: 0)
        } else if context.viewState.showSendButton {
            sendButton
        } else {
            voiceMessageRecordingButton(mode: .idle)
        }
    }
    
    private func sendMessage() {
        // Allow the inner TextField do apply any final processing before
        // sending e.g. accepting current autocorrection.
        // Fixes https://github.com/element-hq/element-x-ios/issues/3216
        context.presendCallback?()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            context.send(viewAction: .sendMessage)
        }
    }
    
    private var placeholder: String {
        // AGENT-PLATFORM (Brief 0083): the field stays under a voice message, hidden, and its placeholder would stay readable.
        guard !context.viewState.isVoiceMessageModeActivated else { return "" }
        
        switch context.viewState.composerMode {
        case .reply(_, _, let isThread):
            return isThread ? L10n.actionReplyInThread : composerPlaceholder
        default:
            return composerPlaceholder
        }
    }
    
    private var composerPlaceholder: String {
        L10n.richTextEditorComposerPlaceholder
    }
    
    private var composerView: WysiwygComposerView {
        WysiwygComposerView(placeholder: placeholder,
                            placeholderColor: SpiralComposerMetrics.chatPlaceholder, // AGENT-PLATFORM (Brief 0083): the field's grey says disabled
                            viewModel: context.viewState.wysiwygViewModel,
                            itemProviderHelper: ItemProviderHelper(),
                            keyCommands: context.viewState.keyCommands) { provider in
            context.send(viewAction: .handlePasteOrDrop(providers: [provider]))
        }
    }
    
    private class ItemProviderHelper: WysiwygItemProviderHelper {
        func isPasteSupported(for itemProvider: NSItemProvider) -> Bool {
            itemProvider.isSupportedForPasteOrDrop
        }
    }
    
    // MARK: - Voice message
    
    @ViewBuilder
    private var voiceMessageContent: some View {
        // Display the voice message composer above to keep the focus and keep the keyboard open if it's already open.
        switch context.viewState.composerMode {
        case .recordVoiceMessage(let state):
            topBarLayout {
                voiceMessageTrashButton
                    .scaledPadding(.vertical, buttonVerticalPadding, relativeTo: .compound.headingLG)
                VoiceMessageRecordingComposer(recorderState: state,
                                              trailing: voiceMessageRecordingButton(mode: .recording)) // AGENT-PLATFORM (Brief 0083)
            }
        case .previewVoiceMessage(let state, let waveform, let isUploading):
            topBarLayout {
                voiceMessageTrashButton
                    .scaledPadding(.vertical, buttonVerticalPadding, relativeTo: .compound.headingLG)
                voiceMessagePreviewComposer(audioPlayerState: state, waveform: waveform)
            }
            .disabled(isUploading)
        default:
            EmptyView()
        }
    }
    
    private func voiceMessageRecordingButton(mode: VoiceMessageRecordingButtonMode) -> some View {
        VoiceMessageRecordingButton(mode: mode) {
            context.send(viewAction: .voiceMessage(.startRecording))
        } stopRecording: {
            context.send(viewAction: .voiceMessage(.stopRecording))
        }
    }
    
    @ViewBuilder
    private var voiceMessagePreviewAction: some View {
        if context.viewState.isUploading {
            ProgressView()
                .spiralComposerAction()
        } else {
            sendButton
        }
    }
    
    private var voiceMessageTrashButton: some View {
        VoiceMessageTrashButton {
            context.send(viewAction: .voiceMessage(.deleteRecording))
        }
        .accessibilityLabel(L10n.a11yDelete)
    }
    
    // AGENT-PLATFORM (Brief 0083): send, or the upload's progress, inside the preview's field.
    private func voiceMessagePreviewComposer(audioPlayerState: AudioPlayerState, waveform: WaveformSource) -> some View {
        VoiceMessagePreviewComposer(playerState: audioPlayerState, waveform: waveform, trailing: voiceMessagePreviewAction) {
            context.send(viewAction: .voiceMessage(.startPlayback))
        } onPause: {
            context.send(viewAction: .voiceMessage(.pausePlayback))
        } onSeek: { progress in
            context.send(viewAction: .voiceMessage(.seekPlayback(progress: progress)))
        } onScrubbing: { isScrubbing in
            context.send(viewAction: .voiceMessage(.scrubPlayback(scrubbing: isScrubbing)))
        }
    }
}

struct ComposerToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            configuration.label
                .modifier(GlassStyle())
        } else {
            configuration.label
                .modifier(FlatStyle(isPressed: configuration.isPressed))
        }
    }
    
    @available(iOS 26, *)
    private struct GlassStyle: ViewModifier {
        @Environment(\.isEnabled) private var isEnabled
        
        func body(content: Content) -> some View {
            if isEnabled {
                label(content: content)
                    .snapshotableGlassEffect(.regular.interactive(),
                                             snapshotBackground: .compound.bgSubtleSecondary,
                                             in: .circle)
            } else {
                // AGENT-PLATFORM: Spiral's bgSubtlePrimary is the canvas white and its iconDisabled #E5E5EA in
                // light mode; disabled is the enabled disc's gray without the glass, the icon in textDisabled.
                label(content: content)
                    .background(.compound.bgSubtleSecondary, in: .circle)
            }
        }
        
        func label(content: Content) -> some View {
            content
                .foregroundStyle(isEnabled ? .compound.iconPrimary : .compound.textDisabled) // AGENT-PLATFORM
                .scaledPadding(10, relativeTo: .compound.headingLG)
        }
    }
    
    private struct FlatStyle: ViewModifier {
        @Environment(\.isEnabled) private var isEnabled
        
        let isPressed: Bool
        
        // AGENT-PLATFORM (Brief 0083): the storyboard's iOS 18 composer (RP-ios18), a dark glyph on a grey
        // 36pt disc, like the glass disc's look in snapshots. It was a white glyph on a filled blue disc.
        func body(content: Content) -> some View {
            content
                .foregroundStyle(isEnabled ? .compound.iconPrimary : .compound.textDisabled)
                .scaledPadding(8, relativeTo: .compound.headingLG)
                .background(.compound.bgSubtleSecondary, in: .circle)
                .opacity(isPressed ? 0.6 : 1)
        }
    }
}

private struct FloatingSuggestions: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    @ObservedObject var context: ComposerToolbarViewModel.Context
    
    var body: some View {
        if verticalSizeClass != .compact, !context.composerExpanded {
            CompletionSuggestionView(mediaProvider: context.mediaProvider,
                                     items: context.viewState.suggestions) { suggestion in
                context.send(viewAction: .selectedSuggestion(suggestion))
            }
            .disabled(!context.viewState.canSend)
        }
    }
}

// MARK: - Previews

struct ComposerToolbar_Previews: PreviewProvider, TestablePreview, SpiralGatedPreview { // AGENT-PLATFORM (Brief 0083): Spiral's gates
    static let timelineViewModel = TimelineViewModel.mock
    
    static let viewModel = ComposerToolbarViewModel.mock()
    static let editingViewModel = ComposerToolbarViewModel.mock(message: "Hello, Wrold!", mockMode: .editing)
    static let multiLineViewModel = ComposerToolbarViewModel.mock(message: "Hello, World! This is a loooong message that wraps onto multiple lines.")
    static let voiceMessageRecordingViewModel = ComposerToolbarViewModel.mock(mockMode: .recordVoiceMessage)
    static let voiceMessagePreviewViewModel = ComposerToolbarViewModel.mock(mockMode: .previewVoiceMessage(isUploading: false))
    static let voiceMessageUploadingViewModel = ComposerToolbarViewModel.mock(mockMode: .previewVoiceMessage(isUploading: true))
    static let replyLoadingViewModel = ComposerToolbarViewModel.mock(mockMode: .reply(isLoading: true))
    static let replyLoadedViewModel = ComposerToolbarViewModel.mock(mockMode: .reply(isLoading: false))
    static let suggestionsViewModel = ComposerToolbarViewModel.mock(hasSuggestions: true)
    static let disabledViewModel = ComposerToolbarViewModel.mock(canSend: false)
    // AGENT-PLATFORM (Brief 0083): one line and five lines typed, and the formatting toolbar open.
    static let oneLineViewModel = ComposerToolbarViewModel.mock(message: "On my way, five minutes")
    static let fiveLinesViewModel = ComposerToolbarViewModel.mock(message: "Here is the plan for tomorrow: we meet at the station at nine, take the first train out, walk the ridge until lunch, and come back down the valley before it gets dark.")
    static let formattingViewModel = {
        let viewModel = ComposerToolbarViewModel.mock()
        viewModel.state.bindings.composerFormattingEnabled = true
        return viewModel
    }()
    
    static var previews: some View {
        VStack(spacing: 8) {
            ComposerToolbar(context: viewModel.context)
            ComposerToolbar(context: editingViewModel.context)
            ComposerToolbar(context: multiLineViewModel.context)
                .padding(.bottom)
            
            ComposerToolbar(context: voiceMessageRecordingViewModel.context)
            ComposerToolbar(context: voiceMessagePreviewViewModel.context)
            ComposerToolbar(context: voiceMessageUploadingViewModel.context)
                .padding(.bottom)
            
            ComposerToolbar(context: disabledViewModel.context)
                // AGENT-PLATFORM: the identity violation disables it asynchronously, after the snapshot (and
                // waiting for it crashes the preview host), so disable it here as `canSend == false` does.
                .disabled(true)
        }
        
        // Putting them in a VStack allows the completion suggestion preview to work properly in tests
        VStack(spacing: 8) {
            ComposerToolbar(context: suggestionsViewModel.context).floatingSuggestions
            ComposerToolbar(context: suggestionsViewModel.context)
        }
        .previewDisplayName("With Suggestions")
        
        VStack(spacing: 8) {
            ComposerToolbar(context: replyLoadingViewModel.context)
            ComposerToolbar(context: replyLoadedViewModel.context)
        }
        .environment(\.timelineContext, timelineViewModel.context)
        .previewDisplayName("Reply")
        
        // AGENT-PLATFORM (Brief 0083): the states the composer's sheet compares.
        VStack(spacing: 8) {
            ComposerToolbar(context: oneLineViewModel.context)
            ComposerToolbar(context: fiveLinesViewModel.context)
        }
        .previewDisplayName("Typing")
        
        VStack(spacing: 8) {
            ComposerToolbar(context: formattingViewModel.context)
        }
        .previewDisplayName("Formatting")
    }
}
