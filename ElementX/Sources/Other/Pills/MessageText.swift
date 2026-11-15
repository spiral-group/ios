//
// Copyright 2025 Element Creations Ltd.
// Copyright 2023-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import MatrixRustSDK
import SwiftUI

final class MessageTextView: UITextView, PillAttachmentViewProviderDelegate, UIGestureRecognizerDelegate, NSLayoutManagerDelegate {
    /// AGENT-PLATFORM (Brief 0083, question 359): text views handed back by the rows that left, for the rows coming in.
    @MainActor
    final class Pool {
        private let capacity: Int
        private var textViews = [MessageTextView]()
        
        init(capacity: Int = 24) {
            self.capacity = capacity
        }
        
        func take() -> MessageTextView {
            textViews.popLast() ?? MessageTextView.make()
        }
        
        func put(_ textView: MessageTextView) {
            textView.prepareForReuse()
            // Next time round, as what's dismantling it still holds it for the rest of this update.
            DispatchQueue.main.async { [self] in
                if textViews.count < capacity {
                    textViews.append(textView)
                }
            }
        }
        
        func purge() {
            textViews.removeAll()
        }
    }
    
    static let pool = Pool()
    
    var timelineContext: TimelineViewModel.Context?
    var updateClosure: (() -> Void)?
    /// AGENT-PLATFORM (Brief 0083, question 359): lazy, as `init(usingTextLayoutManager:)` doesn't run stored properties' initial
    /// values: this stayed nil, so no pill was ever flushed, and a text view that's reused can't keep the last row's.
    private lazy var pillViews = NSHashTable<UIView>.weakObjects()
    
    private static func make() -> MessageTextView {
        // Need to use TextKit 1 for mentions
        let textView = MessageTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        
        // Required to allow tapping links
        // We disable selection at delegate level
        textView.isSelectable = true
        textView.isUserInteractionEnabled = true
        
        // Otherwise links can be dragged and dropped when long pressed
        textView.textDragInteraction?.isEnabled = false
        // Otherwise items dropped onto a bubble land on the text view instead of
        // bubbling up to the timeline's drop handler.
        if let textDropInteraction = textView.textDropInteraction {
            textView.removeInteraction(textDropInteraction)
        }
        
        textView.contentInset = .zero
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.layoutManager.usesFontLeading = false
        textView.layoutManager.delegate = textView
        textView.backgroundColor = .clear
        return textView
    }
    
    /// Leaves nothing of the row it was in.
    private func prepareForReuse() {
        delegate = nil
        timelineContext = nil
        updateClosure = nil
        flushPills()
        removeFromSuperview()
    }
    
    override func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        // We don't need to change the behaviour on MacOS
        if !ProcessInfo.processInfo.isiOSAppOnMac {
            gestureRecognizer.delegate = self
        }
        super.addGestureRecognizer(gestureRecognizer)
    }
    
    /// This prevents the magnifying glass from showing up
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UILongPressGestureRecognizer {
            return false
        }
        return true
    }
    
    func invalidateTextAttachmentsDisplay() {
        attributedText.enumerateAttribute(.attachment,
                                          in: NSRange(location: 0, length: attributedText.length),
                                          options: []) { value, range, _ in
            guard value != nil else {
                return
            }
            self.layoutManager.invalidateDisplay(forCharacterRange: range)
            updateClosure?()
        }
    }
    
    /// Stops TextKit from hyphenating code when a word doesn't fit on a line, wrapping it by
    /// character instead. Code is meant to be verbatim, so an inserted hyphen would corrupt it.
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int) -> Bool {
        guard let textStorage = layoutManager.textStorage, charIndex < textStorage.length else {
            return true
        }
        
        let isCode = textStorage.attribute(.InlineCode, at: charIndex, effectiveRange: nil) != nil
            || textStorage.attribute(.CodeBlock, at: charIndex, effectiveRange: nil) != nil
        return !isCode
    }
    
    func registerPillView(_ pillView: UIView) {
        pillViews.add(pillView)
    }
    
    func flushPills() {
        for view in pillViews.allObjects {
            view.alpha = 0.0
            view.removeFromSuperview()
        }
        pillViews.removeAllObjects()
    }
}

/// An `NSTextAttachment` that takes up its declared `bounds` but draws nothing — used
/// as an invisible spacer so a message bubble's text reserves room for the overlaid
/// timestamp. Without this subclass, an attachment with no image would render TextKit's
/// default "missing image" glyph.
private final nonisolated class TransparentTextAttachment: NSTextAttachment {
    /// AGENT-PLATFORM (Brief 0083, question 359): one for every attachment, as nothing shows of it at any size. Rendering one
    /// for each draw took 0.6 % of the main thread in a scroll on the phone.
    private static let transparentImage = {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in }
    }()
    
    override func image(forBounds imageBounds: CGRect,
                        textContainer: NSTextContainer?,
                        characterIndex charIndex: Int) -> UIImage? {
        Self.transparentImage
    }
}

struct MessageText: UIViewRepresentable {
    @Environment(\.openURL) private var openURLAction
    @Environment(\.timelineContext) private var viewModel
    @Environment(\.layoutDirection) private var layoutDirection
    
    @State var attributedString: AttributedString
    
    /// Reserves an invisible inline area of this size at the very end of the rendered
    /// text. Used so that the message bubble's natural size accommodates the timestamp
    /// overlaid on top of the bubble's bottom-trailing corner. TextKit decides whether
    /// the reserved region fits on the last line (timestamp tucks) or wraps to a new
    /// line (timestamp drops below the text).
    var trailingReservedSize: CGSize = .zero
    
    private func makeAttributedText() -> NSAttributedString? {
        guard let baseText = try? NSAttributedString(attributedString, including: \.elementX) else {
            return nil
        }
        
        let combined = NSMutableAttributedString(attributedString: baseText)
        if trailingReservedSize.width > 0 {
            let attachment = TransparentTextAttachment()
            attachment.isAccessibilityElement = false
            attachment.bounds = CGRect(origin: .zero,
                                       size: CGSize(width: trailingReservedSize.width,
                                                    height: max(trailingReservedSize.height, 1)))
            
            // Inherit the font from the preceding character so the appended runs
            // (newline and attachment) carry the same line metrics as the surrounding
            // text — otherwise a small default font on those characters can shrink the
            // line height and clip e.g. a font-boosted lone emoji.
            let trailingFont = baseText.length > 0
                ? baseText.attribute(.font, at: baseText.length - 1, effectiveRange: nil)
                : nil
            
            // When the last paragraph's natural text direction doesn't match the layout
            // direction, the inline attachment would land on the wrong side and overlap the
            // overlaid timestamp. Force it onto its own line so the bubble just grows taller.
            if !lastParagraphDirectionMatchesLayout(in: combined) {
                let newlineString = NSMutableAttributedString(string: "\n")
                if let trailingFont {
                    newlineString.addAttribute(.font,
                                               value: trailingFont,
                                               range: NSRange(location: 0, length: newlineString.length))
                }
                combined.append(newlineString)
            }
            
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            if let trailingFont {
                attachmentString.addAttribute(.font,
                                              value: trailingFont,
                                              range: NSRange(location: 0, length: attachmentString.length))
            }
            combined.append(attachmentString)
        }
        
        return combined
    }
    
    private func lastParagraphDirectionMatchesLayout(in attributedText: NSAttributedString) -> Bool {
        let string = attributedText.string as NSString
        guard string.length > 0 else { return true }
        
        // Isolate the last paragraph because its direction is what decides
        // which side the trailing attachment ends up on.
        let lastParagraphRange = string.paragraphRange(for: NSRange(location: string.length - 1, length: 0))
        let lastParagraph = string.substring(with: lastParagraphRange)
        
        let textIsRTL = lastParagraph.firstStrongCharacterIsRTL
        let layoutIsRTL = layoutDirection == .rightToLeft
        return textIsRTL == layoutIsRTL
    }
    
    func makeUIView(context: Context) -> MessageTextView {
        // AGENT-PLATFORM (Brief 0083, question 359): a new row's most expensive part, on the phone, was making this view.
        let textView = MessageTextView.pool.take()
        textView.timelineContext = viewModel
        textView.updateClosure = { [weak textView] in
            guard let textView else { return }
            do {
                attributedString = try AttributedString(textView.attributedText, including: \.elementX)
            } catch {
                MXLog.error("Failed to update attributedString: \(error)]")
                return
            }
        }
        textView.delegate = context.coordinator
        context.coordinator.show(content, makeAttributedText, in: textView)
        return textView
    }
    
    func updateUIView(_ uiView: MessageTextView, context: Context) {
        context.coordinator.show(content, makeAttributedText, in: uiView)
        context.coordinator.openURLAction = openURLAction
    }
    
    static func dismantleUIView(_ uiView: MessageTextView, coordinator: Coordinator) {
        MessageTextView.pool.put(uiView)
    }
    
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MessageTextView, context: Context) -> CGSize? {
        let proposalWidth = proposal.width ?? UIView.layoutFittingExpandedSize.width
        return context.coordinator.size(forWidth: proposalWidth, of: uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(openURLAction: openURLAction)
    }
    
    /// What the text view is showing, so that an update bringing the same has nothing to do.
    private var content: Coordinator.Content {
        .init(attributedString: attributedString, trailingReservedSize: trailingReservedSize, layoutDirection: layoutDirection)
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        struct Content: Equatable {
            let attributedString: AttributedString
            let trailingReservedSize: CGSize
            let layoutDirection: LayoutDirection
        }
        
        var openURLAction: OpenURLAction
        private var content: Content?
        /// By the proposed width, for what the text view is showing. A value here rather than state, as writing state
        /// from a measure renders the row again.
        private var sizes = [CGFloat: CGSize]()
        
        init(openURLAction: OpenURLAction) {
            self.openURLAction = openURLAction
        }
        
        /// Shows the content unless that's what the text view has, which spares the conversion of an update bringing nothing new.
        func show(_ content: Content, _ makeAttributedText: () -> NSAttributedString?, in textView: MessageTextView) {
            guard content != self.content else { return }
            let isFirstContent = self.content == nil
            self.content = content
            sizes.removeAll()
            
            // A text view from the pool still has the text of the row it was in.
            if let attributedText = makeAttributedText() ?? (isFirstContent ? NSAttributedString() : nil), textView.attributedText != attributedText {
                textView.flushPills()
                textView.attributedText = attributedText
            }
        }
        
        func size(forWidth width: CGFloat, of textView: MessageTextView) -> CGSize {
            if let size = sizes[width] {
                return size
            }
            
            let size = textView.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height))
            sizes[width] = size
            return size
        }
        
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !ProcessInfo.processInfo.isiOSAppOnMac else {
                return
            }
            textView.selectedTextRange = nil
        }
        
        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content {
                return .init(title: defaultAction.title,
                             image: defaultAction.image,
                             discoverabilityTitle: defaultAction.discoverabilityTitle,
                             attributes: defaultAction.attributes,
                             state: defaultAction.state) { [weak self] _ in
                    self?.openURLAction.callAsFunction(url)
                }
            }
            return defaultAction
        }
        
        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            switch textItem.content {
            case let .link(url):
                guard !url.requiresConfirmation else {
                    return nil
                }
                // We don't want to show a URL preview for permalinks
                // AGENT-PLATFORM (Brief 0060): resolves both namespaces
                // (spiral.md smart links + inbound matrix.to).
                let isPermalink = SpiralLink.matrixLinkTarget(from: url) != nil
                return .init(preview: isPermalink ? nil : .default, menu: defaultMenu)
            default:
                return nil
            }
        }
    }
}

// MARK: - Previews

struct MessageText_Previews: PreviewProvider, TestablePreview {
    private static let defaultFontContainer: AttributeContainer = {
        var container = AttributeContainer()
        container.font = UIFont.preferredFont(forTextStyle: .body)
        return container
    }()
    
    private static let attributedString = AttributedString("Hello World! Hello world! Hello world! Hello world! Hello World! Hellooooooooooooooooooooooo Woooooooooooooooooooooorld", attributes: defaultFontContainer)
    
    private static let attributedStringWithAttachment: AttributedString = {
        let testData = PillTextAttachmentData(type: .user(userID: "@alice:example.com"), font: .preferredFont(forTextStyle: .body))
        guard let attachment = PillTextAttachment(attachmentData: testData) else {
            return AttributedString()
        }
        
        var attributedString = "Hello test test test " + AttributedString(NSAttributedString(attachment: attachment)) + " World!"
        attributedString
            .mergeAttributes(defaultFontContainer)
        return attributedString
    }()
    
    private static let htmlStringWithQuote =
        """
        <blockquote>A blockquote that is long and goes onto multiple lines as the first item in the message</blockquote><p>Then another line of text here to reply to the blockquote, which is also a multiline component.</p>
        """
    
    private static let htmlStringWithList = "<p>This is a list</p>\n<ul><li>One</li>\n<li>Two</li>\n<li>And number 3</li>\n</ul>\n"
    
    private static let attributedStringBuilder = AttributedStringBuilder(mentionBuilder: MentionBuilder())
    
    static var attachmentPreview: some View {
        MessageText(attributedString: attributedStringWithAttachment)
            .border(Color.purple)
            .environmentObject(TimelineViewModel.mock.context)
    }
    
    static var previews: some View {
        MessageText(attributedString: attributedString)
            .border(Color.purple)
            .previewDisplayName("Custom Text")
        // For comparison
        Text(attributedString)
            .border(Color.purple)
            .previewDisplayName("SwiftUI Default Text")
        attachmentPreview
            .previewDisplayName("Custom Attachment")
        if let attributedString = attributedStringBuilder.fromHTML(htmlStringWithQuote) {
            MessageText(attributedString: attributedString)
                .border(Color.purple)
                .previewDisplayName("With block quote")
        }
        if let attributedString = attributedStringBuilder.fromHTML(htmlStringWithList) {
            MessageText(attributedString: attributedString)
                .border(Color.purple)
                .previewDisplayName("With list")
        }
    }
}
