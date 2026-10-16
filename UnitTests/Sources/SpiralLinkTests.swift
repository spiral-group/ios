//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM: Brief 0060 / ADR-0072 — Spiral link namespace codec.
// The identifier shapes pinned here mirror `src/api/routes/links.rs`
// on the backend; if one side changes, the other must change with it.
//

@testable import ElementX
import Foundation
import Testing

struct SpiralLinkTests {
    // Real identifiers taken from the production docs so the fixtures
    // match what Synapse actually generates.
    private let roomLocalpart = "PGBmctdJNFwoAOHtvM"
    private let eventLocalpart = "WUzJ-abZT4jooldYohZlI8ueLnHGrng5De38aiOg31M"
    
    // MARK: - Building
    
    @Test
    func buildsProfileLinkFromMXID() throws {
        let link = try #require(SpiralLink(userID: "@telegram_123456789:spiral.md"))
        
        #expect(link == .user(localpart: "telegram_123456789"))
        #expect(link.webURL?.absoluteString == "https://spiral.md/@telegram_123456789")
        #expect(link.schemeURL?.absoluteString == "spiral:///@telegram_123456789")
        #expect(link.matrixIdentifier == "@telegram_123456789:spiral.md")
    }
    
    @Test
    func refusesToMintLinksForForeignHomeservers() {
        #expect(SpiralLink(userID: "@alice:matrix.org") == nil)
        #expect(SpiralLink(roomID: "!abc:matrix.org", canonicalAlias: nil) == nil)
        #expect(SpiralLink(roomID: "!abc:matrix.org", canonicalAlias: "#room:matrix.org") == nil)
    }
    
    @Test
    func prefersCanonicalAliasOverRoomID() throws {
        let link = try #require(SpiralLink(roomID: "!\(roomLocalpart):spiral.md",
                                           canonicalAlias: "#general:spiral.md"))
        
        #expect(link == .roomAlias(alias: "general"))
        #expect(link.webURL?.absoluteString == "https://spiral.md/c/general")
        #expect(link.matrixIdentifier == "#general:spiral.md")
    }
    
    @Test
    func fallsBackToRoomIDWithoutAlias() throws {
        let link = try #require(SpiralLink(roomID: "!\(roomLocalpart):spiral.md", canonicalAlias: nil))
        
        #expect(link == .room(roomLocalpart: roomLocalpart))
        #expect(link.webURL?.absoluteString == "https://spiral.md/!\(roomLocalpart)")
        #expect(link.matrixIdentifier == "!\(roomLocalpart):spiral.md")
    }
    
    @Test
    func fallsBackToRoomIDWhenAliasIsForeign() throws {
        let link = try #require(SpiralLink(roomID: "!\(roomLocalpart):spiral.md",
                                           canonicalAlias: "#room:matrix.org"))
        
        #expect(link == .room(roomLocalpart: roomLocalpart))
    }
    
    /// Room version 12 dropped the `:server` suffix from room IDs.
    /// Sharing must keep working the day Synapse flips its default, and
    /// the round trip must not silently re-attach a domain that the
    /// room ID never had.
    @Test
    func handlesRoomVersion12IdentifiersWithoutADomain() throws {
        let hashedRoomID = "AAqRfsRDGVHZXJXcRsLGXNtVGVzdDEyMzQ1Njc4OTAx"
        #expect(hashedRoomID.count == 43)
        
        let link = try #require(SpiralLink(roomID: "!\(hashedRoomID)", canonicalAlias: nil))
        #expect(link == .room(roomLocalpart: hashedRoomID))
        #expect(link.webURL?.absoluteString == "https://spiral.md/!\(hashedRoomID)")
        #expect(link.matrixIdentifier == "!\(hashedRoomID)")
        
        let webURL = try #require(link.webURL)
        let parsed = try #require(SpiralLink.parse(webURL))
        #expect(parsed.matrixIdentifier == "!\(hashedRoomID)")
        
        // Pre-v12 IDs keep the implied homeserver.
        #expect(SpiralLink(roomID: "!\(roomLocalpart):spiral.md", canonicalAlias: nil)?
            .matrixIdentifier == "!\(roomLocalpart):spiral.md")
    }
    
    @Test
    func buildsEventPermalinkFromRoomIDNotAlias() throws {
        let link = try #require(SpiralLink(roomID: "!\(roomLocalpart):spiral.md",
                                           eventID: "$\(eventLocalpart)"))
        
        #expect(link == .event(roomLocalpart: roomLocalpart, eventLocalpart: eventLocalpart))
        #expect(link.webURL?.absoluteString == "https://spiral.md/!\(roomLocalpart)/$\(eventLocalpart)")
    }
    
    // MARK: - Parsing (round trip)
    
    @Test
    func parsesEveryGeneratedShape() throws {
        let links: [SpiralLink] = [
            .user(localpart: "telegram_123456789"),
            .roomAlias(alias: "general"),
            .room(roomLocalpart: roomLocalpart),
            .event(roomLocalpart: roomLocalpart, eventLocalpart: eventLocalpart)
        ]
        
        for link in links {
            let webURL = try #require(link.webURL)
            let schemeURL = try #require(link.schemeURL)
            
            #expect(SpiralLink.parse(webURL) == link)
            #expect(SpiralLink.parse(schemeURL) == link)
        }
    }
    
    @Test
    func rejectsForeignHostsAndSchemes() throws {
        let rejected = [
            "https://spiral.md.evil.com/@alice",
            "https://evil.com/@alice",
            "https://matrix.to/#/@alice:spiral.md",
            "http://spiral.md/@alice",
            "ftp://spiral.md/@alice",
            "element://user/@alice:spiral.md",
            // Two slashes make Foundation read `@alice` as userinfo.
            "spiral://@alice"
        ]
        
        for urlString in rejected {
            let url = try #require(URL(string: urlString))
            #expect(SpiralLink.parse(url) == nil, "\(urlString) must not parse")
        }
    }
    
    @Test
    func rejectsMalformedPaths() throws {
        let rejected = [
            "https://spiral.md/",
            "https://spiral.md/@",
            "https://spiral.md/alice",
            "https://spiral.md/@alice/extra",
            "https://spiral.md/!\(roomLocalpart)/\(eventLocalpart)",
            "https://spiral.md/!\(roomLocalpart)/$\(eventLocalpart)/extra",
            "https://spiral.md/c",
            "https://spiral.md/c/general/extra",
            "https://spiral.md/brand/privacy",
            "https://spiral.md/api/v1/agents",
            // The alias sigil can never appear in a path — it starts
            // the fragment, so the server sees nothing.
            "https://spiral.md/#general"
        ]
        
        for urlString in rejected {
            let url = try #require(URL(string: urlString))
            #expect(SpiralLink.parse(url) == nil, "\(urlString) must not parse")
        }
    }
    
    @Test
    func rejectsIdentifiersOutsideTheGrammar() throws {
        // Uppercase + sigils + traversal are all outside the user
        // localpart grammar; room IDs keep their mixed case.
        #expect(SpiralLink.parse(try #require(URL(string: "https://spiral.md/@Alice"))) == nil)
        #expect(SpiralLink.parse(try #require(URL(string: "https://spiral.md/@@alice"))) == nil)
        #expect(SpiralLink.parse(try #require(URL(string: "https://spiral.md/c/%23general"))) == nil)
        #expect(SpiralLink.parse(try #require(URL(string: "https://spiral.md/!..%2Fetc"))) == nil)
        #expect(SpiralLink.parse(try #require(URL(string: "https://spiral.md/!\(roomLocalpart)"))) != nil)
    }
    
    @Test
    func validatesLocalpartGrammar() {
        #expect(SpiralLink.validUserLocalpart("telegram_123456789"))
        #expect(SpiralLink.validUserLocalpart("assistant-alice"))
        #expect(SpiralLink.validUserLocalpart("alice.example"))
        #expect(!SpiralLink.validUserLocalpart(""))
        #expect(!SpiralLink.validUserLocalpart("UPPER"))
        #expect(!SpiralLink.validUserLocalpart("with space"))
        #expect(!SpiralLink.validUserLocalpart("with/slash"))
        #expect(!SpiralLink.validUserLocalpart(String(repeating: "a", count: 256)))
        #expect(!SpiralLink.validUserLocalpart("кирилиця"))
        
        #expect(SpiralLink.validRoomLocalpart(roomLocalpart))
        #expect(SpiralLink.validEventLocalpart(eventLocalpart))
        #expect(!SpiralLink.validRoomLocalpart("room:spiral.md"))
        #expect(!SpiralLink.validRoomLocalpart("room#frag"))
    }
}
