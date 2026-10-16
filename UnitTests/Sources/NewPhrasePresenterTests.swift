//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0075 — how the identity page's return is read.
//

@testable import ElementX
import Foundation
import Testing

struct NewPhrasePresenterTests {
    @Test
    func aChangedPhraseIsReportedAsChanged() {
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://phrase-changed?result=changed")) == .changed)
    }
    
    @Test
    func everythingElseIsACancel() {
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://phrase-changed?result=cancelled")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://phrase-changed")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: URL(string: "spiral://join/abc?result=changed")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: URL(string: "https://phrase-changed?result=changed")) == .cancelled)
        #expect(NewPhrasePresenter.outcome(for: nil) == .cancelled)
    }
}
