//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI
import WysiwygComposer

typealias GenericKeyHandler = (_ key: UIKeyboardHIDUsage) -> Void
typealias PasteHandler = ([NSItemProvider]) -> Void

struct MessageComposer<Trailing: View>: View { // AGENT-PLATFORM (Brief 0083): the field's action is inside it
    @Binding var plainComposerText: NSAttributedString
    @Binding var presendCallback: (() -> Void)?
    @Binding var selectedRange: NSRange
    
    let composerView: WysiwygComposerView
    let mode: ComposerMode
    let placeholder: String
    
    let composerFormattingEnabled: Bool
    let showResizeGrabber: Bool
    @Binding var isExpanded: Bool
    let trailing: Trailing // AGENT-PLATFORM (Brief 0083): send or the microphone, inside the field's trailing end
    
    let sendAction: () -> Void
    let editAction: () -> Void
    let pasteAction: PasteHandler
    let cancellationAction: () -> Void
    let onAppearAction: () -> Void
    
    @State private var composerTranslation: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            if showResizeGrabber {
                resizeGrabber
            }
            
            composerTextField
                // AGENT-PLATFORM (Brief 0083): on the field only, so the send button in its trailing end keeps its own.
                .accessibilityIdentifier(A11yIdentifiers.roomScreen.messageComposer)
                .messageComposerStyle(header: header, trailing: trailing) // AGENT-PLATFORM (Brief 0083): Spiral's composer field
                // Explicitly disable all animations to fix weirdness with the header immediately
                // appearing whilst the text field and keyboard are still animating up to it.
                .animation(.noAnimation, value: mode)
        }
        .gesture(showResizeGrabber ? dragGesture : nil)
    }
    
    // MARK: - Private
    
    @State private var composerFrame = CGRect.zero
    
    @ViewBuilder
    private var composerTextField: some View {
        if composerFormattingEnabled {
            Color.clear
                .overlay(alignment: .top) {
                    composerView
                        .clipped()
                        .readFrame($composerFrame)
                }
                .frame(minHeight: ComposerConstant.minHeight, maxHeight: max(composerHeight, composerFrame.height),
                       alignment: .top)
                .onAppear {
                    onAppearAction()
                }
        } else {
            MessageComposerTextField(placeholder: placeholder,
                                     text: $plainComposerText,
                                     presendCallback: $presendCallback,
                                     selectedRange: $selectedRange,
                                     maxHeight: ComposerConstant.maxHeight,
                                     keyHandler: { handleKeyPress($0) },
                                     pasteHandler: pasteAction,
                                     placeholderColor: SpiralComposerMetrics.chatPlaceholder) // AGENT-PLATFORM (Brief 0083, question 359)
        }
    }
    
    private var composerHeight: CGFloat {
        let baseHeight = isExpanded ? ComposerConstant.maxHeight : ComposerConstant.minHeight
        return (baseHeight - composerTranslation).clamped(to: ComposerConstant.allowedHeightRange)
    }
    
    @ViewBuilder
    private var header: some View {
        switch mode {
        case .reply(_, let replyDetails, _):
            MessageComposerReplyHeader(replyDetails: replyDetails, action: cancellationAction)
        case .edit(_, let editType):
            MessageComposerEditHeader(editType: editType, action: cancellationAction)
        case .recordVoiceMessage, .previewVoiceMessage, .default:
            EmptyView()
        }
    }
    
    private var resizeGrabber: some View {
        Capsule()
            .foregroundStyle(.tertiary)
            .frame(width: 36, height: 5)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                composerTranslation += value.translation.height
            }
            .onEnded { _ in
                withElementAnimation(.easeIn(duration: 0.3)) {
                    if composerTranslation > ComposerConstant.translationThreshold {
                        isExpanded = false
                    } else if composerTranslation < -ComposerConstant.translationThreshold {
                        isExpanded = true
                    }
                    composerTranslation = 0
                }
            }
    }
    
    private func handleKeyPress(_ key: UIKeyboardHIDUsage) {
        switch key {
        case .keyboardReturnOrEnter:
            sendAction()
        case .keyboardUpArrow:
            editAction()
        case .keyboardEscape:
            cancellationAction()
        default:
            break
        }
    }
}

private struct MessageComposerReplyHeader: View {
    let replyDetails: TimelineItemReplyDetails
    let action: () -> Void
    
    // AGENT-PLATFORM (Brief 0083): the timeline's quote in a translucent block above the text, its close button inside.
    // The close button sat over the quote's top trailing corner.
    var body: some View {
        SpiralComposerHeader(closeLabel: L10n.actionClose, close: action) {
            TimelineReplyView(placement: .composer, timelineItemReplyDetails: replyDetails, maxWidth: .infinity)
        }
    }
}

private struct MessageComposerEditHeader: View {
    let editType: ComposerMode.EditType
    let action: () -> Void
    
    private var title: String {
        switch editType {
        case .default: L10n.commonEditing
        case .addCaption: L10n.commonAddingCaption
        case .editCaption: L10n.commonEditingCaption
        }
    }
    
    var body: some View {
        SpiralComposerHeader(closeLabel: L10n.actionClose, close: action) { // AGENT-PLATFORM (Brief 0083): the reply's block, its close button inside
            Label(title, icon: \.editSolid, iconSize: .xSmall, relativeTo: .compound.bodySMSemibold)
                .labelStyle(MessageComposerHeaderLabelStyle())
        }
    }
}

private struct MessageComposerHeaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 4) {
            configuration.icon
            configuration.title
        }
        .font(.compound.bodySMSemibold)
        .foregroundColor(.compound.textSecondary)
        .lineLimit(1)
    }
}

// MARK: - Previews

struct MessageComposer_Previews: PreviewProvider, TestablePreview {
    static let viewModel = TimelineViewModel.mock
    
    static let replyTypes: [TimelineItemReplyDetails] = [
        .loaded(sender: .init(id: "Dave"),
                eventID: "123",
                eventContent: .message(.audio(.init(filename: "lightning.mp3",
                                                    caption: "Audio: Ride the lightning",
                                                    duration: 100,
                                                    waveform: nil,
                                                    source: nil,
                                                    fileSize: nil,
                                                    contentType: nil)))),
        .loaded(sender: .init(id: "James"),
                eventID: "123",
                eventContent: .message(.emote(.init(body: "Emote: James thinks he's the phantom lord")))),
        .loaded(sender: .init(id: "Robert"),
                eventID: "123",
                eventContent: .message(.file(.init(filename: "brain-surgery.pdf",
                                                   caption: "File: Crash course in brain surgery",
                                                   source: nil,
                                                   fileSize: nil,
                                                   thumbnailSource: nil,
                                                   contentType: nil)))),
        .loaded(sender: .init(id: "Cliff"),
                eventID: "123",
                eventContent: .message(.image(.init(filename: "head.png",
                                                    caption: "Image: Pushead",
                                                    imageInfo: .mockImage,
                                                    thumbnailInfo: .mockThumbnail)))),
        .loaded(sender: .init(id: "Jason"),
                eventID: "123",
                eventContent: .message(.notice(.init(body: "Notice: Too far gone?")))),
        .loaded(sender: .init(id: "Kirk"),
                eventID: "123",
                eventContent: .message(.text(.init(body: "Text: Where the wild things are")))),
        .loaded(sender: .init(id: "Lars"),
                eventID: "123",
                eventContent: .message(.video(.init(filename: "never.mov",
                                                    caption: "Video: Through the never",
                                                    videoInfo: .mockVideo,
                                                    thumbnailInfo: .mockVideoThumbnail)))),
        .loading(eventID: "")
    ]
    
    static func messageComposer(_ content: NSAttributedString = .init(string: ""),
                                mode: ComposerMode = .default,
                                placeholder: String = L10n.richTextEditorComposerPlaceholder) -> MessageComposer<EmptyView> { // AGENT-PLATFORM (Brief 0083)
        let viewModel = WysiwygComposerViewModel(minHeight: 22,
                                                 maxExpandedHeight: 250)
        viewModel.setMarkdownContent(content.string)
        
        let composerView = WysiwygComposerView(placeholder: L10n.richTextEditorComposerPlaceholder,
                                               viewModel: viewModel,
                                               itemProviderHelper: nil,
                                               keyCommands: nil,
                                               pasteHandler: nil)
        
        return MessageComposer(plainComposerText: .constant(content),
                               presendCallback: .constant(nil),
                               selectedRange: .constant(NSRange(location: 0, length: 0)),
                               composerView: composerView,
                               mode: mode,
                               placeholder: placeholder,
                               composerFormattingEnabled: false,
                               showResizeGrabber: false,
                               isExpanded: .constant(false),
                               trailing: EmptyView(), // AGENT-PLATFORM (Brief 0083)
                               sendAction: { },
                               editAction: { },
                               pasteAction: { _ in },
                               cancellationAction: { },
                               onAppearAction: { viewModel.setup() })
    }
    
    static var previews: some View {
        VStack(spacing: 8) {
            messageComposer()
            
            messageComposer(.init(string: "Some message"),
                            mode: .edit(originalEventOrTransactionID: .eventID(UUID().uuidString), type: .default))
            
            let longMessage = "Short loin ground round tongue hamburger, fatback salami shoulder. Beef turkey sausage kielbasa strip steak. Alcatra capicola pig tail pancetta chislic."
            messageComposer(.init(string: longMessage),
                            mode: .edit(originalEventOrTransactionID: .eventID(UUID().uuidString), type: .default))
            
            messageComposer(mode: .reply(eventID: UUID().uuidString,
                                         replyDetails: .loaded(sender: .init(id: "Kirk"),
                                                               eventID: "123",
                                                               eventContent: .message(.text(.init(body: "Text: Where the wild things are")))),
                                         isThread: false))
            
            messageComposer(.init(string: "Some new caption"),
                            mode: .edit(originalEventOrTransactionID: .eventID(UUID().uuidString), type: .addCaption))
            messageComposer(.init(string: "Some updated caption"),
                            mode: .edit(originalEventOrTransactionID: .eventID(UUID().uuidString), type: .editCaption))
        }
        .padding(.horizontal)
        .environment(\.timelineContext, viewModel.context)
        
        ScrollView {
            VStack(spacing: 8) {
                ForEach(replyTypes, id: \.self) { replyDetails in
                    messageComposer(mode: .reply(eventID: UUID().uuidString,
                                                 replyDetails: replyDetails, isThread: false))
                }
            }
        }
        .padding(.horizontal)
        .environment(\.timelineContext, viewModel.context)
        .previewDisplayName("Replying")
        
        ScrollView {
            VStack(spacing: 8) {
                ForEach(replyTypes, id: \.self) { replyDetails in
                    messageComposer(mode: .reply(eventID: UUID().uuidString,
                                                 replyDetails: replyDetails, isThread: true),
                                    placeholder: L10n.actionReplyInThread)
                }
            }
        }
        .padding(.horizontal)
        .environment(\.timelineContext, viewModel.context)
        .previewDisplayName("Replying in thread")
    }
}
