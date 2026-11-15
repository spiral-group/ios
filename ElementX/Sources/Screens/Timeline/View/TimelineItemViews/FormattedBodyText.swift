//
// Copyright 2025 Element Creations Ltd.
// Copyright 2022-2025 New Vector Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

import Compound
import SwiftUI

struct FormattedBodyText: View {
    @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083)
    @Environment(\.isTimelineItemPinned) private var isPinned // AGENT-PLATFORM (Brief 0083, question 359)
    
    private let attributedString: AttributedString
    private let trailingReservedSize: CGSize
    private let boostFontSize: Bool
    
    private var reservedSize: CGSize {
        guard isPinned, trailingReservedSize != .zero else { return trailingReservedSize }
        return CGSize(width: trailingReservedSize.width + TimelineItemSendInfo.pinSlotWidth, height: trailingReservedSize.height)
    }
    
    private var defaultAttributesContainer: AttributeContainer { // AGENT-PLATFORM (Brief 0083): computed, it reads the bubble
        var container = AttributeContainer()
        // Equivalent to compound's bodyLG
        container.font = UIFont.preferredFont(forTextStyle: .body)
        container.foregroundColor = ownBubbleInk.map { UIColor($0.text) } ?? UIColor.compound.textPrimary // AGENT-PLATFORM (Brief 0083)
        return container
    }
    
    private var attributedComponents: [AttributedStringBuilderComponent] {
        var adjustedAttributedString = attributedString
        
        // AGENT-PLATFORM (Brief 0083, decision 300a): on an own blue bubble the text is white, so code keeps
        // its dark text on the code background, and links, as white as the text, are underlined.
        if let ownBubbleInk {
            adjustedAttributedString.keepCodeColours()
            for (link, range) in adjustedAttributedString.runs[\.link] where link != nil {
                adjustedAttributedString[range].uiKit.underlineStyle = .single
            }
        }
        
        // Required to allow the underlying TextView to use  body font when no font is specified in the AttributedString.
        adjustedAttributedString.mergeAttributes(defaultAttributesContainer, mergePolicy: .keepCurrent)
        
        let string = String(attributedString.characters)
        
        if boostFontSize, let range = adjustedAttributedString.range(of: string) {
            adjustedAttributedString[range].font = UIFont.systemFont(ofSize: 48.0)
        }
        
        return adjustedAttributedString.formattedComponents
    }
    
    init(attributedString: AttributedString,
         trailingReservedSize: CGSize = .zero,
         boostFontSize: Bool = false) {
        self.attributedString = attributedString
        self.trailingReservedSize = trailingReservedSize
        self.boostFontSize = boostFontSize
    }
    
    init(text: String, trailingReservedSize: CGSize = .zero, boostFontSize: Bool = false) {
        self.init(attributedString: AttributedString(text),
                  trailingReservedSize: trailingReservedSize,
                  boostFontSize: boostFontSize)
    }
    
    /// Details components contain a control that VoiceOver needs to reach, so their children can't be merged away.
    private var containsDetails: Bool {
        attributedString.runs[\.details].contains { $0.0 != nil }
    }
    
    var body: some View {
        layout
            .tint(ownBubbleInk?.link ?? .compound.textLinkExternal) // AGENT-PLATFORM (Brief 0083)
            .accessibilityElement(children: containsDetails ? .contain : .ignore)
            .accessibilityLabel(Text(attributedString))
    }
    
    /// The attributed components laid out for the bubbles timeline style.
    @ViewBuilder
    var layout: some View {
        let components = layoutComponents
        // AGENT-PLATFORM (Brief 0083, question 359): most messages are one run of plain text, which has nothing to lay out.
        if components.count == 1, let component = components.first, component.type == .plainText {
            plainText(component, trailingReservedSize: reservedSize)
                .id(component.id)
        } else {
            layout(components)
        }
    }
    
    private var layoutComponents: [AttributedStringBuilderComponent] {
        // The trailing reserved area must only be applied to the last plain text
        // component so that the bubble's natural size accommodates the overlaid
        // timestamp, and TextKit decides whether to keep the timestamp on the last
        // line or push it to a new one.
        var components = attributedComponents
        // When the body ends in a block component (blockquote/codeBlock) the overlaid
        // timestamp would land on top of it, so append an empty trailing plain-text
        // component that exists solely to reserve space for the timestamp underneath.
        if trailingReservedSize != .zero, let last = components.last, last.type != .plainText {
            components.append(AttributedStringBuilderComponent(id: "",
                                                               attributedString: AttributedString(),
                                                               type: .plainText))
        }
        return components
    }
    
    private func plainText(_ component: AttributedStringBuilderComponent, trailingReservedSize: CGSize) -> some View {
        MessageText(attributedString: component.attributedString, trailingReservedSize: trailingReservedSize)
            .padding(.horizontal, 4)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    private func layout(_ components: [AttributedStringBuilderComponent]) -> some View {
        let lastPlainTextIndex = components.lastIndex { $0.type == .plainText }
        
        return TimelineBubbleLayout(spacing: 8) {
            // The `ForEach` needs to iterate over the id of the element to allow
            // SwiftUI animations to work properly ater any edit.
            ForEach(Array(components.enumerated()), id: \.element.id) { index, component in
                switch component.type {
                case .blockquote:
                    BlockquoteView(attributedString: component.attributedString, mode: .rendering)
                        .timelineBubbleLayoutSize(.bubbleWidth(mode: .rendering))
                case .codeBlock:
                    CodeBlockView(attributedString: component.attributedString, mode: .rendering)
                        .timelineBubbleLayoutSize(.bubbleWidth(mode: .rendering))
                        .contextMenu {
                            Button(L10n.actionCopy) {
                                UIPasteboard.general.string = component.attributedString.string
                            }
                        }
                case .details(let summary):
                    DetailsView(summary: summary, attributedString: component.attributedString)
                        .padding(.horizontal, 4)
                        .timelineBubbleLayoutSize(.natural)
                case .plainText:
                    plainText(component, trailingReservedSize: index == lastPlainTextIndex ? reservedSize : .zero)
                        .timelineBubbleLayoutSize(.natural)
                }
            }
            
            // Make a second iteration through the components adding naturally sized versions of the
            // block quotes and code blocks which are used for layout calculations but won't be rendered.
            ForEach(components) { component in
                switch component.type {
                case .blockquote:
                    BlockquoteView(attributedString: component.attributedString, mode: .layout)
                        .timelineBubbleLayoutSize(.bubbleWidth(mode: .layout))
                        .hidden()
                case .codeBlock:
                    CodeBlockView(attributedString: component.attributedString, mode: .layout)
                        .timelineBubbleLayoutSize(.bubbleWidth(mode: .layout))
                        .hidden()
                case .details, .plainText:
                    EmptyView()
                }
            }
        }
    }
    
    // MARK: - Component Views
    
    /// The view used to render a blockquote component. It can be configured in one of 2 modes:
    /// - `.layout`: The view is given it's natural size to be used for layout calculations.
    /// - `.rendering`: The view has a greedy width that, in combination with the custom layout,
    /// will fill any available space, whilst remaining constrained by the bubble's calculated width.
    struct BlockquoteView: View {
        @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083)
        
        let attributedString: AttributedString
        let mode: TimelineBubbleLayout.Size.BubbleWidthMode
        
        var body: some View {
            MessageText(attributedString: quotedString) // AGENT-PLATFORM (Brief 0083)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: mode == .rendering ? .infinity : nil, alignment: .leading)
                .padding(.leading, 12.0)
                .overlay(alignment: .leading) {
                    // Use an overlay here so that the rectangle's infinite height doesn't take priority
                    if mode == .rendering {
                        Capsule()
                            .frame(width: 2.0)
                            .padding(.leading, 5.0)
                            .foregroundColor(quoteColor) // AGENT-PLATFORM (Brief 0083)
                            .padding(.vertical, 2)
                    }
                }
        }
        
        private var blockquoteAttributes: AttributeContainer {
            // The paragraph style removes the block style paragraph that the parser adds by default
            // Set directly in the constructor to avoid `Conformance to 'Sendable'` warnings
            var container = AttributeContainer([.paragraphStyle: NSParagraphStyle.default])
            // Sadly setting SwiftUI fonts do not work so we would need UIFont equivalents for compound, this one is bodyMD
            container.font = UIFont.preferredFont(forTextStyle: .subheadline)
            container.foregroundColor = ownBubbleInk.map { UIColor($0.secondaryText) } ?? UIColor.compound.textSecondary // AGENT-PLATFORM (Brief 0083)
            
            return container
        }
        
        // AGENT-PLATFORM (Brief 0083, decision 300a): grey would fall under 4.5:1 on an own blue bubble.
        private var quoteColor: Color {
            ownBubbleInk?.secondaryText ?? .compound.textSecondary
        }
        
        // AGENT-PLATFORM (Brief 0083, decision 300a): the quote's colour replaces every run's, so on an own
        // bubble code in a quote turned white on its white background; it gets its own colours back.
        private var quotedString: AttributedString {
            var string = attributedString.mergingAttributes(blockquoteAttributes)
            if ownBubbleInk != nil {
                string.keepCodeColours()
            }
            return string
        }
    }
    
    /// The view used to render a `<details>` component, collapsing its content behind its `<summary>`.
    private struct DetailsView: View {
        @Environment(\.ownBubbleInk) private var ownBubbleInk // AGENT-PLATFORM (Brief 0083)
        
        let summary: String
        let attributedString: AttributedString
        
        @State private var isExpanded = false
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button { isExpanded.toggle() } label: {
                    HStack(alignment: .center, spacing: 4) {
                        CompoundIcon(\.chevronRight, size: .xSmall, relativeTo: .compound.bodyLG)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(summary)
                    }
                    .font(.compound.bodyLGSemibold)
                    .foregroundStyle(ownBubbleInk?.text ?? .compound.textPrimary) // AGENT-PLATFORM (Brief 0083)
                }
                .buttonStyle(.plain)
                
                if isExpanded {
                    MessageText(attributedString: attributedString)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    /// The view used to render a code block component. It can be configured in one of 2 modes:
    /// - `.layout`: The view is given it's natural size to be used for layout calculations.
    /// - `.rendering`: The view has a greedy width that, in combination with the custom layout,
    /// will fill any available space, whilst remaining constrained by the bubble's calculated width.
    private struct CodeBlockView: View {
        let attributedString: AttributedString
        let mode: TimelineBubbleLayout.Size.BubbleWidthMode
        
        @State private var maxWidth: CGFloat = .zero
        
        var body: some View {
            ScrollView(.horizontal) {
                MessageText(attributedString: attributedString)
                    .padding([.horizontal, .top], 4)
                    .padding(.bottom, 8)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { maxWidth = $0 }
            }
            .frame(maxWidth: mode == .layout ? maxWidth : nil)
            .background(.compound._bgCodeBlock)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollIndicatorsFlash(onAppear: true)
            .padding(.horizontal, 4)
        }
    }
}

// AGENT-PLATFORM (Brief 0083, decision 300a)
extension AttributedString {
    /// On an own blue bubble the text is white; code keeps its dark text where the code background is drawn: under
    /// inline code, and in a code block that is its own component (`CodeBlockView`). A `<pre>` inside a quote or a
    /// `<details>` has no background there, so it stays in the text's colour (3.5:1 dark on the blue otherwise).
    mutating func keepCodeColours() {
        for (isCode, range) in runs[\.inlineCode] where isCode == true {
            self[range].uiKit.foregroundColor = .compound.textPrimary
        }
        for (isCodeBlock, blockquote, details, range) in runs[\.codeBlock, \.blockquote, \.details]
            where isCodeBlock == true && blockquote == nil && details == nil {
            self[range].uiKit.foregroundColor = .compound.textPrimary
        }
    }
}

// MARK: - Previews

struct FormattedBodyText_Previews: PreviewProvider, TestablePreview {
    static let attributedStringBuilder = AttributedStringBuilder(cacheKey: "FormattedBodyText", mentionBuilder: MentionBuilder())
    static var previews: some View {
        htmlFixtures
        
        basicText
            .previewLayout(.sizeThatFits)
            .previewDisplayName("basicText")
        
        singleColumnComponents
            .previewLayout(.sizeThatFits)
            .previewDisplayName("singleColumnComponents")
    }
    
    static var basicText: some View {
        VStack(alignment: .leading, spacing: 4.0) {
            FormattedBodyText(attributedString: AttributedString("Some plain text wrapped in an AttributedString."))
                .bubbleBackground()
            
            FormattedBodyText(text: "Some plain text that's not an attributed component.")
                .bubbleBackground()
            
            FormattedBodyText(text: "❤️", boostFontSize: true)
                .bubbleBackground()
        }
        .padding()
    }
    
    /// A preview to help ensure that none of the component types we support result
    /// in a bubble's width becoming wider than the natural width of its contents.
    @ViewBuilder
    static var singleColumnComponents: some View {
        let html = """
        <blockquote>A</blockquote>
        <pre><code>B</code></pre>
        <p>C</p>
        <details><summary>D</summary><p>E</p></details>
        """
        
        if let attributedString = attributedStringBuilder.fromHTML(html) {
            FormattedBodyText(attributedString: attributedString)
                .bubbleBackground()
                .padding(4.0)
        }
    }
    
    @ViewBuilder
    static var htmlFixtures: some View {
        let htmlFixtures = HTMLFixtures.allCases
        
        ForEach(htmlFixtures, id: \.rawValue) { htmlFixture in
            HStack(alignment: .top, spacing: 0) {
                let htmlString = htmlFixture.rawValue
                Text(htmlString)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .padding(4.0)
                
                Divider()
                    .background(.black)
                
                if let attributedString = attributedStringBuilder.fromHTML(htmlString) {
                    FormattedBodyText(attributedString: attributedString)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .bubbleBackground()
                        .padding(4.0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .border(.black)
            .padding()
            .previewLayout(.sizeThatFits)
            .previewDisplayName("\(htmlFixture)")
        }
    }
}
