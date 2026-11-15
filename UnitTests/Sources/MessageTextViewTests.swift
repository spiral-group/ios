//
// Copyright 2026 Element Creations Ltd.
//
// SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
// Please see LICENSE files in the repository root for full details.
//

@testable import Spiral
import SwiftUI
import Testing

struct MessageTextViewTests {
    private let attributedStringBuilder = AttributedStringBuilder(mentionBuilder: MentionBuilder())
    private let textView = MessageTextView(usingTextLayoutManager: false)
    
    @Test
    func inlineCodeIsNotHyphenated() throws {
        let textStorage = try makeTextStorage(html: "Merged at <code>d097cc7a2720e8a6e0714d291aa27a034bd20a0b</code> today")
        let layoutManager = try #require(textStorage.layoutManagers.first)
        
        let codeRange = (textStorage.string as NSString).range(of: "d097cc7a2720e8a6e0714d291aa27a034bd20a0b")
        for index in codeRange.location..<NSMaxRange(codeRange) {
            #expect(!textView.layoutManager(layoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt: index))
        }
    }
    
    @Test
    func codeBlockIsNotHyphenated() throws {
        let textStorage = try makeTextStorage(html: "<pre>configurationmanagementinitialization</pre>")
        let layoutManager = try #require(textStorage.layoutManagers.first)
        
        let codeRange = (textStorage.string as NSString).range(of: "configurationmanagementinitialization")
        for index in codeRange.location..<NSMaxRange(codeRange) {
            #expect(!textView.layoutManager(layoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt: index))
        }
    }
    
    @Test
    func plainTextCanStillBeHyphenated() throws {
        let textStorage = try makeTextStorage(html: "Internationalization <code>code</code> incomprehensibilities")
        let layoutManager = try #require(textStorage.layoutManagers.first)
        let string = textStorage.string as NSString
        
        #expect(textView.layoutManager(layoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt: string.range(of: "Internationalization").location + 5))
        #expect(textView.layoutManager(layoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt: string.range(of: "incomprehensibilities").location + 5))
    }
    
    @Test
    func outOfBoundsIndexIsIgnored() throws {
        let textStorage = try makeTextStorage(html: "<code>code</code>")
        let layoutManager = try #require(textStorage.layoutManagers.first)
        
        #expect(textView.layoutManager(layoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt: textStorage.length))
    }
    
    // MARK: - The pool (AGENT-PLATFORM, Brief 0083, question 359)
    
    @Test
    func aTextViewHandedBackIsHandedOutAgain() async {
        let pool = MessageTextView.Pool()
        let textView = pool.take()
        
        pool.put(textView)
        await mainQueue()
        
        let isSameView = pool.take() === textView
        #expect(isSameView)
    }
    
    @Test
    func aTextViewIsNotHandedOutInTheUpdateThatDismantledIt() {
        let pool = MessageTextView.Pool()
        let textView = pool.take()
        
        pool.put(textView)
        
        let isSameView = pool.take() === textView
        #expect(!isSameView)
    }
    
    @Test
    func aTextViewHandedBackKeepsNothingOfItsRow() {
        let pool = MessageTextView.Pool()
        let textView = pool.take()
        let delegate = MessageText.Coordinator(openURLAction: OpenURLAction { _ in .handled })
        let superview = UIView()
        superview.addSubview(textView)
        textView.delegate = delegate
        textView.timelineContext = TimelineViewModel.mock.context
        textView.updateClosure = { }
        let pill = UIView()
        textView.registerPillView(pill)
        textView.addSubview(pill)
        
        pool.put(textView)
        
        // As values: `#expect` can't describe a text view.
        let hasDelegate = textView.delegate != nil
        let hasContext = textView.timelineContext != nil
        let hasClosure = textView.updateClosure != nil
        let hasSuperview = textView.superview != nil
        let hasPill = pill.superview != nil
        #expect(!hasDelegate)
        #expect(!hasContext)
        #expect(!hasClosure)
        #expect(!hasSuperview)
        #expect(!hasPill)
    }
    
    @Test
    func thePoolKeepsNoMoreThanItsCapacity() async {
        let pool = MessageTextView.Pool(capacity: 1)
        let first = pool.take()
        let second = pool.take()
        
        pool.put(first)
        pool.put(second)
        await mainQueue()
        
        let isFirstKept = pool.take() === first
        let isSecondKept = pool.take() === second
        #expect(isFirstKept)
        #expect(!isSecondKept)
    }
    
    // MARK: - What the view shows (AGENT-PLATFORM, Brief 0083, question 359)
    
    @Test
    func theSameContentIsConvertedOnce() {
        let coordinator = makeCoordinator()
        var conversions = 0
        
        for _ in 0..<3 {
            coordinator.show(content("Hello"), {
                conversions += 1
                return NSAttributedString(string: "Hello")
            }, in: textView)
        }
        
        #expect(conversions == 1)
        #expect(textView.attributedText.string == "Hello")
    }
    
    @Test
    func aChangeOfTheReservedSizeOrTheDirectionConvertsItAgain() {
        let coordinator = makeCoordinator()
        var conversions = 0
        let convert = {
            conversions += 1
            return NSAttributedString(string: "Hello")
        }
        
        coordinator.show(content("Hello"), convert, in: textView)
        coordinator.show(content("Hello", reservedWidth: 40), convert, in: textView)
        coordinator.show(content("Hello", reservedWidth: 40, layoutDirection: .rightToLeft), convert, in: textView)
        
        #expect(conversions == 3)
    }
    
    @Test
    func aTextViewFromThePoolShowsNothingOfTheLastRowWhenItsTextFails() {
        textView.attributedText = NSAttributedString(string: "The last row's")
        
        makeCoordinator().show(content("Hello"), { nil }, in: textView)
        
        #expect(textView.attributedText.string.isEmpty)
    }
    
    @Test
    func aFailedUpdateLeavesTheTextThatsThere() {
        let coordinator = makeCoordinator()
        coordinator.show(content("Hello"), { NSAttributedString(string: "Hello") }, in: textView)
        
        coordinator.show(content("Goodbye"), { nil }, in: textView)
        
        #expect(textView.attributedText.string == "Hello")
    }
    
    @Test
    func aSizeFollowsTheTextAndTheWidth() {
        let coordinator = makeCoordinator()
        textView.font = .systemFont(ofSize: 17)
        coordinator.show(content("Hi"), { NSAttributedString(string: "Hi", attributes: [.font: UIFont.systemFont(ofSize: 17)]) }, in: textView)
        let short = coordinator.size(forWidth: 300, of: textView)
        
        let longText = String(repeating: "A longer message. ", count: 20)
        coordinator.show(content(longText), { NSAttributedString(string: longText, attributes: [.font: UIFont.systemFont(ofSize: 17)]) }, in: textView)
        let long = coordinator.size(forWidth: 300, of: textView)
        let narrow = coordinator.size(forWidth: 100, of: textView)
        
        #expect(long.height > short.height)
        #expect(narrow.height > long.height)
    }
    
    // MARK: - Helpers
    
    private func makeCoordinator() -> MessageText.Coordinator {
        MessageText.Coordinator(openURLAction: OpenURLAction { _ in .handled })
    }
    
    private func content(_ text: String, reservedWidth: CGFloat = 0, layoutDirection: LayoutDirection = .leftToRight) -> MessageText.Coordinator.Content {
        .init(attributedString: AttributedString(text), trailingReservedSize: CGSize(width: reservedWidth, height: 0), layoutDirection: layoutDirection)
    }
    
    private func mainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    
    /// The layout manager only holds a weak reference to its text storage, so the storage is what must be kept alive.
    private func makeTextStorage(html: String) throws -> NSTextStorage {
        let attributedString = try #require(attributedStringBuilder.fromHTML(html))
        let textStorage = try NSTextStorage(attributedString: NSAttributedString(attributedString, including: \.elementX))
        textStorage.addLayoutManager(NSLayoutManager())
        return textStorage
    }
}
