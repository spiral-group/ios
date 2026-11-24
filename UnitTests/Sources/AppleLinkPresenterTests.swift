//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (1.0.3): how the identity page's return from adding Sign in with Apple is read.
//

import Foundation
@testable import Spiral
import Testing

struct AppleLinkPresenterTests {
    @Test
    func aLinkedAppleIDIsReportedAsLinked() {
        #expect(AppleLinkPresenter.outcome(for: URL(string: "spiral://apple-linked?result=linked")) == .linked)
    }
    
    @Test
    func anAppleIDOnAnotherAccountIsTaken() {
        #expect(AppleLinkPresenter.outcome(for: URL(string: "spiral://apple-linked?result=taken")) == .taken)
    }
    
    /// The web session never sees anything but an `https` page: `ASWebAuthenticationSession`
    /// raises an exception on another scheme.
    @Test
    func onlyAnHttpsPageOpens() throws {
        #expect(try IdentityPageSession.canOpen(#require(URL(string: "https://id.spiral.md/link/apple?ticket=t"))))
        #expect(try !IdentityPageSession.canOpen(#require(URL(string: "http://id.spiral.md/link/apple"))))
        #expect(try !IdentityPageSession.canOpen(#require(URL(string: "spiral://apple-linked?result=linked"))))
        #expect(try !IdentityPageSession.canOpen(#require(URL(string: "https:///no-host"))))
    }
    
    @Test
    func everythingElseIsACancel() {
        #expect(AppleLinkPresenter.outcome(for: URL(string: "spiral://apple-linked?result=cancelled")) == .cancelled)
        #expect(AppleLinkPresenter.outcome(for: URL(string: "spiral://apple-linked?result=unlinked")) == .cancelled)
        #expect(AppleLinkPresenter.outcome(for: URL(string: "spiral://apple-linked")) == .cancelled)
        #expect(AppleLinkPresenter.outcome(for: URL(string: "spiral://phrase-changed?result=linked")) == .cancelled)
        #expect(AppleLinkPresenter.outcome(for: URL(string: "https://apple-linked?result=linked")) == .cancelled)
        #expect(AppleLinkPresenter.outcome(for: nil) == .cancelled)
    }
}
