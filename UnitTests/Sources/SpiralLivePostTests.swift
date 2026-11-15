//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (§ 5.55): a published post knows its thread, and the thread
// knows which post it now edits.
//

import Foundation
import MatrixRustSDK
@testable import Spiral
import Testing

@MainActor
struct SpiralLivePostTests {
    @Test
    func aManifestNamesTheThreadItWasMadeIn() throws {
        let json = #"{"app_id":"gen-abc","runtime":"1","entry":"app.jsx","aspect":"1:1","state_channel":"matrix","capabilities":[],"limits":{"max_state_bytes":16384},"origin":{"room_id":"!dm:spiral.md","thread_root":"$root"}}"#
        let manifest = try #require(SpiralAppManifest(json: Data(json.utf8)))

        #expect(manifest.origin == SpiralAppOrigin(roomID: "!dm:spiral.md", threadRootEventID: "$root"))
    }

    @Test
    func aManifestFromBeforeHasNoOrigin() throws {
        let json = #"{"app_id":"gen-abc","runtime":"1","entry":"app.jsx","capabilities":[]}"#
        let manifest = try #require(SpiralAppManifest(json: Data(json.utf8)))

        #expect(manifest.origin == nil)
    }

    /// The note the client writes, read back the way a thread timeline reads
    /// it: from the raw event, as the server returns it.
    @Test
    func aMarkerSurvivesTheRoundTrip() throws {
        let live = SpiralLivePost(roomID: "!group:spiral.md", eventID: "$post", roomName: "Група")
        let content = try #require(live.markerContent(action: "editing", body: "Changing «Табло» in «Група»", threadRootEventID: "$root"))
        let event = "{\"type\":\"m.room.message\",\"content\":\(content)}"

        #expect(SpiralLivePost(eventJSON: event) == live)

        let object = try #require(try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])
        #expect((object["body"] as? String)?.hasPrefix(SpiralLivePost.bodyPrefix) == true,
                "a timeline only asks for the raw JSON of texts that start like a marker")
        let relation = try #require(object["m.relates_to"] as? [String: Any])
        #expect(relation["rel_type"] as? String == "m.thread")
        #expect(relation["event_id"] as? String == "$root")
        #expect((object[SpiralLivePost.contentKey] as? [String: Any])?["action"] as? String == "editing")
    }

    @Test
    func anOrdinaryMessageIsNotAMarker() {
        #expect(SpiralLivePost(eventJSON: #"{"type":"m.room.message","content":{"msgtype":"m.text","body":"📌 hi"}}"#) == nil)
        #expect(SpiralLivePost(eventJSON: "not json") == nil)
    }

    /// A new post goes out raw so the thread can be told its event id; the
    /// raw content must be the shape the SDK writes, or other clients would
    /// not read it as a post.
    @Test
    func aRawPostHasTheSDKsShape() throws {
        let post = InteractivePostContent(body: "Табло", appId: "gen-abc", runtime: "1", title: "Табло", aspect: "1:1",
                                          stateChannel: "matrix", sha256: "ab12", url: nil,
                                          fileJson: #"{"url":"mxc://spiral.md/x","key":{"k":"secret"},"iv":"i","hashes":{"sha256":"h"},"v":"v2"}"#)
        let raw = try #require(SpiralAppPublisher.rawPostContent(post))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])

        #expect(object["msgtype"] as? String == "com.spiral.app")
        #expect(object["body"] as? String == "Табло")
        #expect(object["sha256"] as? String == "ab12")
        #expect(object["aspect"] as? String == "1:1")
        #expect((object["file"] as? [String: Any])?["url"] as? String == "mxc://spiral.md/x",
                "the encrypted file travels as an object, not a string")
        #expect(object["url"] == nil)

        // And the SDK reads it back as the post it was.
        let fromSDK = SpiralAppPost(post)
        #expect(fromSDK.digest == "ab12")
    }
}

@MainActor
struct SpiralAppCatalogTests {
    /// `/catalog/index.json` as `pnpm catalog:pack` writes it.
    @Test
    func theCatalogueReadsAsThePackerWritesIt() throws {
        let json = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","items":["dice"]}],"items":[{"id":"dice","title":"Кубик","description":"Кидок d6","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json","row":"dice/row.png"}]}"#
        let catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(json.utf8))

        #expect(catalog.sections.first?.items == ["dice"])
        #expect(catalog.template("dice")?.manifest == "dice/manifest.json")
        #expect(catalog.template("nope") == nil)
        // A catalogue from before § 5.59 has no translations: the base text.
        #expect(catalog.template("dice")?.localizedTitle == "Кубик")
    }

    /// The app's language picks the text; a language the catalogue does not
    /// carry gets the base text (§ 5.59).
    @Test
    func theCatalogueSpeaksTheAppsLanguage() throws {
        let json = #"{"version":1,"runtime":"1","sections":[{"id":"decide","title":"Вирішити","titles":{"ru":"Решить","en":"Decide"},"items":["dice"]}],"items":[{"id":"dice","title":"Кубик","titles":{"ru":"Кубик","en":"Dice"},"description":"Кидок d6","descriptions":{"ru":"Бросок d6","en":"Roll a d6"},"aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json","row":"dice/row.png"}]}"#
        let catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(json.utf8))
        defer { Bundle.overrideLocalizations = nil }

        Bundle.overrideLocalizations = ["en"]
        #expect(catalog.template("dice")?.localizedTitle == "Dice")
        #expect(catalog.sections.first?.localizedTitle == "Decide")

        Bundle.overrideLocalizations = ["ru"]
        #expect(catalog.template("dice")?.localizedDescription == "Бросок d6")
        #expect(catalog.sections.first?.localizedTitle == "Решить")

        Bundle.overrideLocalizations = ["uk"]
        #expect(catalog.template("dice")?.localizedDescription == "Кидок d6")

        // Any other language reads the English the rest of the app shows.
        Bundle.overrideLocalizations = ["de"]
        #expect(catalog.sections.first?.localizedTitle == "Decide")
    }

    /// The seed the agent answers with Draft v1: code outside the text, in
    /// the thread, under the key the orchestrator reads.
    @Test
    func aSeedGoesIntoTheThreadWithItsCode() throws {
        let seed = RoomFlowCoordinator.InteractiveSeed(title: "Табло", aspect: "4:3", source: "export default () => null;")
        let content = try #require(RoomFlowCoordinator.seedContent(seed, threadRootEventID: "$root"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any])

        #expect((object["m.relates_to"] as? [String: Any])?["event_id"] as? String == "$root")
        let carried = try #require(object["com.spiral.seed"] as? [String: Any])
        #expect(carried["source"] as? String == "export default () => null;")
        #expect(carried["aspect"] as? String == "4:3")
        #expect(carried["asks"] == nil, "a template that needs nothing asks nothing")

        var asking = seed
        asking.asks = "Яке питання й які варіанти?"
        let withAsk = try #require(RoomFlowCoordinator.seedContent(asking, threadRootEventID: "$root"))
        let askObject = try #require(try JSONSerialization.jsonObject(with: Data(withAsk.utf8)) as? [String: Any])
        #expect((askObject["com.spiral.seed"] as? [String: Any])?["asks"] as? String == "Яке питання й які варіанти?")
    }

    /// The root says the app's language, for the words that do not (§ 5.60).
    @Test
    func aRequestRootCarriesTheAppsLanguage() throws {
        let content = RoomFlowCoordinator.interactivePostRequestContent(targetRoomID: "!r:spiral.md",
                                                                        targetRoomName: "Public 0067",
                                                                        members: [],
                                                                        language: "ru")
        let request = try #require(content["com.spiral.interactive"] as? [String: Any])
        #expect(request["language"] as? String == "ru")
        #expect(request["v"] as? Int == 1, "the same record, one field more")

        defer { Bundle.overrideLocalizations = nil }
        Bundle.overrideLocalizations = ["uk"]
        #expect(SpiralAppMount.appLanguage == "uk")
        Bundle.overrideLocalizations = ["pt-BR"]
        #expect(SpiralAppMount.appLanguage == "pt", "a primary subtag")
    }

    /// A template that is only a shape asks in the app's language; the rest
    /// ask nothing (§ 5.60).
    @Test
    func aTemplateAsksInTheAppsLanguage() throws {
        let json = #"{"version":1,"runtime":"1","sections":[],"items":[{"id":"poll","title":"Голосування","description":"…","aspect":"4:3","source":"poll/app.jsx","manifest":"poll/manifest.json","row":"poll/row.png","asks":{"uk":"Яке питання?","ru":"Какой вопрос?","en":"What's the question?"}},{"id":"dice","title":"Кубик","description":"…","aspect":"1:1","source":"dice/app.jsx","manifest":"dice/manifest.json","row":"dice/row.png"}]}"#
        let catalog = try JSONDecoder().decode(SpiralAppCatalog.self, from: Data(json.utf8))
        defer { Bundle.overrideLocalizations = nil }

        Bundle.overrideLocalizations = ["ru"]
        #expect(catalog.template("poll")?.localizedAsk == "Какой вопрос?")
        Bundle.overrideLocalizations = ["de"]
        #expect(catalog.template("poll")?.localizedAsk == "What's the question?")
        #expect(catalog.template("dice")?.localizedAsk == nil)
    }
}
