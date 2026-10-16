//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 5.1): the app's view of a post.
//
// Reading the EVENT is the SDK's job now — an Interactive Post is a message
// type, so its claims arrive typed the way an image's dimensions do, and the
// malformed cases are refused in Rust before any client sees them
// (`interactive_post_tests` in `bindings/matrix-sdk-ffi/src/ruma.rs`).
//
// What is left here is the one thing the app decides for itself: where the
// bytes are. `source` lets every caller ask that without minding whether the
// room was encrypted, and getting the precedence wrong would send a client to
// fetch plaintext that cannot be decrypted.
//

@testable import ElementX
import Foundation
import MatrixRustSDK
import Testing

struct SpiralAppPostTests {
    private static let digest = String(repeating: "a", count: 64)

    private static func content(url: String? = nil, fileJSON: String? = nil, title: String = "Куди їдемо?", runtime: String = "1") -> InteractivePostContent {
        InteractivePostContent(body: "Куди їдемо?",
                               appId: "poll",
                               runtime: runtime,
                               title: title,
                               aspect: "4:3",
                               stateChannel: "matrix",
                               sha256: digest,
                               url: url,
                               fileJson: fileJSON)
    }

    /// A post from a runtime this build does not carry is known as such,
    /// so the row keeps its card instead of booting a module it cannot run
    /// (§ 5.70, OPEN #25).
    @Test
    func aPostFromAnotherRuntimeIsNotRunnable() {
        #expect(SpiralAppPost(Self.content(url: "mxc://spiral.md/abc")).isRuntimeSupported)
        #expect(!SpiralAppPost(Self.content(url: "mxc://spiral.md/abc", runtime: "2")).isRuntimeSupported)
        #expect(SpiralAppPost(Self.content(url: "mxc://spiral.md/abc", runtime: "1.1")).isRuntimeSupported, "the games level")
        #expect(!SpiralAppPost(Self.content(url: "mxc://spiral.md/abc", runtime: "1.9")).isRuntimeSupported, "a level from a later build")
    }

    /// A catalogue carries what a later build can run; this one lists only
    /// what it can, and a section left empty goes (§ 5.75).
    @Test
    func theCatalogueListsOnlyWhatThisBuildCanRun() throws {
        let json = """
        {"runtime":"1","sections":[{"id":"play","title":"Пограти","items":["chess","later"]},{"id":"soon","title":"Скоро","items":["later"]}],
         "items":[{"id":"chess","title":"Шахи","description":"","aspect":"1:1","source":"chess/app.jsx","manifest":"chess/manifest.json","runtime":"1.1"},
                  {"id":"later","title":"Потім","description":"","aspect":"1:1","source":"later/app.jsx","manifest":"later/manifest.json","runtime":"1.9"}]}
        """
        let catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(json.utf8)).runnable
        #expect(catalog.items.map(\.id) == ["chess"])
        #expect(catalog.sections.map(\.id) == ["play"])
        #expect(catalog.sections.first?.items == ["chess"])
    }

    // MARK: - Adopting what the SDK read

    @Test
    func everyClaimSurvivesTheCrossing() {
        let post = SpiralAppPost(Self.content(url: "mxc://spiral.md/abc"))

        #expect(post.appID == "poll")
        #expect(post.runtime == "1")
        #expect(post.title == "Куди їдемо?")
        #expect(post.aspect == "4:3")
        #expect(post.stateChannel == "matrix")
        #expect(post.digest == Self.digest)
    }

    @Test
    func anUnencryptedPostPointsAtItsMedia() {
        let post = SpiralAppPost(Self.content(url: "mxc://spiral.md/abc"))

        #expect(post.source == .plain("mxc://spiral.md/abc"))
    }

    @Test
    func anEncryptedPostCarriesTheFileItCanDecrypt() {
        let file = #"{"url":"mxc://spiral.md/enc","key":{"k":"…"}}"#
        let post = SpiralAppPost(Self.content(fileJSON: file))

        #expect(post.source == .encrypted(Data(file.utf8)))
    }

    @Test
    func theEncryptedFileWinsWhenBothAreOffered() {
        // A sender may include both. Only one of them can be decrypted, and
        // choosing the plaintext would send the client to fetch bytes it
        // cannot read — a failure that looks like a network problem.
        let file = #"{"url":"mxc://spiral.md/enc","key":{"k":"…"}}"#
        let post = SpiralAppPost(Self.content(url: "mxc://spiral.md/plain", fileJSON: file))

        #expect(post.source == .encrypted(Data(file.utf8)))
    }

    @Test
    func theEncryptedFileIsHandedToTheSDKUnderFileSoItDecrypts() throws {
        // An `EncryptedFile` has a `url` of its own. Handed to
        // `MediaSource.fromJson` bare, ruma reads it as a PLAIN source and the
        // ciphertext comes back as the artifact — the first published draft
        // failed its digest check exactly so.
        let file = #"{"url":"mxc://spiral.md/enc","key":{"k":"…"},"iv":"iv","hashes":{"sha256":"h"},"v":"v2"}"#
        let post = SpiralAppPost(Self.content(fileJSON: file))

        let json = try #require(post.source.mediaSourceJSON)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["url"] == nil)
        let wrapped = try #require(object["file"] as? [String: Any])
        #expect(wrapped["url"] as? String == "mxc://spiral.md/enc")
        #expect(wrapped["v"] as? String == "v2")

        let plain = SpiralAppPost(Self.content(url: "mxc://spiral.md/abc"))
        let plainJSON = try #require(plain.source.mediaSourceJSON)
        let plainObject = try #require(JSONSerialization.jsonObject(with: Data(plainJSON.utf8)) as? [String: Any])
        #expect(plainObject["url"] as? String == "mxc://spiral.md/abc")
        #expect(plainObject["file"] == nil)
    }

    @Test
    func theMediaURLIsReadableWhicheverShapeItTook() {
        let file = #"{"url":"mxc://spiral.md/enc","key":{"k":"…"}}"#

        #expect(SpiralAppPost(Self.content(url: "mxc://spiral.md/abc")).source.mxcURL == "mxc://spiral.md/abc")
        #expect(SpiralAppPost(Self.content(fileJSON: file)).source.mxcURL == "mxc://spiral.md/enc")
    }

    // MARK: - Sizing a row before anything loads

    @Test
    func aspectDecidesTheRowsShapeBeforeTheArtifactArrives() {
        #expect(Self.isRatio(SpiralAppPost(Self.content(url: "mxc://x")).aspectRatio, 4.0 / 3.0))
    }

    @Test
    func anAspectThatSaysNothingUsableIsRefusedRatherThanGuessed() {
        // A zero or a nonsense ratio would collapse the row or divide by zero.
        // `nil` lets the view fall back to something it chose deliberately.
        for nonsense in ["", "4", "4:0", "0:3", "wide:tall", "4:3:2"] {
            var content = Self.content(url: "mxc://x")
            content.aspect = nonsense
            #expect(SpiralAppPost(content).aspectRatio == nil, "\(nonsense) was taken seriously")
        }
    }

    /// A manifest asks for a shape; the host decides what the row takes.
    ///
    /// Without this a post could be 22pt tall across a phone — controls too
    /// small to hit, text with nowhere to go — and the author would have no
    /// way to know they had done it.
    @Test
    func aShapeNobodyCouldUseIsBroughtBackToOneTheyCan() {
        let cases: [(String, CGFloat)] = [
            ("4:3", 4.0 / 3.0), // asked for and granted
            ("1:1", 1),
            ("16:1", SpiralAppPost.widestAspectRatio), // a strip
            ("1:16", SpiralAppPost.narrowestAspectRatio), // a column
            ("4:0", 1), // nonsense falls back rather than dividing by zero
            ("", 1)
        ]

        for (aspect, expected) in cases {
            var content = Self.content(url: "mxc://x")
            content.aspect = aspect
            let ratio = SpiralAppPost(content).displayAspectRatio
            #expect(abs(ratio - expected) < 0.0001, "\(aspect) became \(ratio), wanted \(expected)")
        }
    }

    // MARK: - Telling a post from anything else

    @Test
    func aPostIsRecognisedFromItsRawEvent() {
        // The event-cache observer hands out text, not typed content — it sits
        // below the typed layer so that actions can be seen at all.
        #expect(SpiralAppPost.isPost(rawEventJSON: Self.rawMessage(msgtype: "com.spiral.app")))
    }

    @Test
    func anOrdinaryMessageIsNotAPost() {
        #expect(SpiralAppPost.isPost(rawEventJSON: Self.rawMessage(msgtype: "m.text")) == false)
    }

    @Test
    func anActionIsNotAPost() {
        // The two are deliberately different kinds of thing: one is a message
        // and a row, the other is state and must never be either.
        let action = """
        {"type":"com.spiral.app.action","event_id":"$a","sender":"@a:s.md",
         "origin_server_ts":1,"content":{"seq":1}}
        """
        #expect(SpiralAppPost.isPost(rawEventJSON: action) == false)
    }

    @Test
    func rubbishIsNotAPost() {
        #expect(SpiralAppPost.isPost(rawEventJSON: "not json") == false)
        #expect(SpiralAppPost.isPost(rawEventJSON: "{}") == false)
    }

    // MARK: - Helpers

    private static func rawMessage(msgtype: String) -> String {
        """
        {"type":"m.room.message","event_id":"$post","sender":"@a:spiral.md",
         "origin_server_ts":1,"content":{"msgtype":"\(msgtype)","body":"Куди їдемо?"}}
        """
    }

    private static func isRatio(_ value: CGFloat?, _ expected: CGFloat) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 0.0001
    }
}
