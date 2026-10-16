//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (decision 146): the base of the dev-stack E2E suite. Every
// test refuses to start unless it runs on a Spiral-Dev-* simulator with the
// fixture the runner wrote for this run, and every app launch carries
// SPIRAL_DEV_STACK=1 — without it the Debug build talks to prod.
//

import XCTest

/// What `Tools/Scripts/run-dev-e2e.sh` prepared for this run: the accounts,
/// the host helper and the simulator it expects. A 0600 file whose path
/// comes in `SPIRAL_E2E_FIXTURE`; passwords stay in their own files.
struct DevE2EFixture: Decodable {
    struct Person: Decodable {
        let localpart: String
        let mxid: String
        let displayName: String
        /// A 0600 file holding the password (password accounts only).
        let passwordFile: String?
    }

    let env: String
    let runID: String
    let simulatorUDID: String
    let helperURL: URL
    let helperToken: String
    let owner: Person
    let peer: Person
    let registrant: Person
    /// Registers in the app through the owner's own invitation (G5).
    let newcomer: Person
    /// First-contact visitors of the owner's assistant, one per approval
    /// scenario (G13, G14): a card decided once cannot be made again by the
    /// same person (decision 148).
    let visitors: [Person]
    let inviteCode: String
    /// A one-seat campaign of this run: S1 registers through it, G4 finds
    /// it used up.
    let onceInviteCode: String
    let catalogTemplate: String
}

enum DevE2EError: Error, CustomStringConvertible {
    case refused(String)
    case helper(String)
    case flow(String)

    var description: String {
        switch self {
        case .refused(let why): "refused: \(why)"
        case .helper(let why): "helper: \(why)"
        case .flow(let why): why
        }
    }
}

@MainActor
class DevE2ETestCase: XCTestCase {
    private static let refusedNames: Set = ["Spiral-Invite-B", "Spiral-Olena-2"]
    private static let refusedUDIDs: Set = ["D38F9D70-5189-43B6-9CD1-7D1B5E55FC7A", "7E78D059-EC82-4FDF-BD86-EAC069BA18F7"]
    static let bundleID = "com.veruslogistics.messenger"

    private(set) var fixture: DevE2EFixture!
    private(set) var helper: DevE2EHelper!
    var app: XCUIApplication!

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let webView = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false

        let environment = ProcessInfo.processInfo.environment
        guard let name = environment["SIMULATOR_DEVICE_NAME"], name.hasPrefix("Spiral-Dev-"), !Self.refusedNames.contains(name) else {
            throw DevE2EError.refused("not a Spiral-Dev-* simulator (\(environment["SIMULATOR_DEVICE_NAME"] ?? "unknown"))")
        }
        guard let udid = environment["SIMULATOR_UDID"], !Self.refusedUDIDs.contains(udid) else {
            throw DevE2EError.refused("a prod-signed simulator or no SIMULATOR_UDID")
        }
        guard let path = environment["SPIRAL_E2E_FIXTURE"], !path.isEmpty else {
            throw DevE2EError.refused("no SPIRAL_E2E_FIXTURE: run Tools/Scripts/run-dev-e2e.sh")
        }
        let fixture = try JSONDecoder().decode(DevE2EFixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard fixture.env == "dev" else { throw DevE2EError.refused("the fixture is not for the dev stack") }
        guard fixture.simulatorUDID == udid else { throw DevE2EError.refused("the fixture was written for another simulator") }
        guard fixture.helperURL.host == "127.0.0.1" else { throw DevE2EError.refused("the helper is not on 127.0.0.1") }
        for person in [fixture.owner, fixture.peer, fixture.registrant, fixture.newcomer] + fixture.visitors where !person.mxid.hasSuffix(":localhost") {
            throw DevE2EError.refused("\(person.mxid) is not a dev account")
        }

        self.fixture = fixture
        helper = DevE2EHelper(baseURL: fixture.helperURL, token: fixture.helperToken)
        try await helper.ping()
        // Decision 149: the scripted AI mock, when the runner has one, answers
        // by this scenario's rules ("testS04AssistantChat" → S04,
        // "testG13aEditDraftThenSend" → G13).
        let testName = self.name // `name` above is the simulator's
        if let scenario = testName.range(of: "test[SG][0-9]{2}", options: .regularExpression).map({ String(testName[$0].dropFirst(4)) }) {
            try await helper.mock(scenario: scenario)
        }
    }

    // Synchronous on purpose: an async tearDown that took a screenshot hung
    // the run for ten minutes (2026-10-12). XCTest calls it on the main thread.
    // No screenshot while the sign-in phrase is on screen (S01, G5 failing
    // on identity-login's phrase steps): the test plan keeps no system
    // attachments or screen recordings for the same reason.
    override func tearDownWithError() throws {
        let png = MainActor.assumeIsolated { () -> Data? in
            let phrase = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService").staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Write these 12 words' OR label BEGINSWITH 'Pick word #'"))
            return phrase.firstMatch.exists ? nil : XCUIScreen.main.screenshot().pngRepresentation
        }
        if let png {
            let shot = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            shot.name = "last screen of \(name)"
            shot.lifetime = .keepAlways
            add(shot)
        } else {
            let note = XCTAttachment(string: "not kept: the sign-in phrase was on screen")
            note.name = "last screen of \(name)"
            add(note)
        }
        try super.tearDownWithError()
    }
    
    // MARK: - Launch

    /// Starts the app on the dev stack, in English, and has the helper read
    /// the running process: a launch without the variable is killed and fails.
    @discardableResult
    func launchApp(arguments: [String] = []) async throws -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundleID)
        app.launchEnvironment["SPIRAL_DEV_STACK"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        self.app = app
        try await helper.sim("check-dev")
        return app
    }

    /// Opens a `spiral://` link on this run's simulator. The helper confirms
    /// SpringBoard's «Open in "Spiral"?», but it looks for it only 3 s: a later
    /// sheet is confirmed here (S01 waited on it, 2026-10-14).
    /// With `target`, waits for it instead (a toast is gone within seconds)
    /// and says whether it showed.
    @discardableResult
    func openLink(_ url: String, thenWaitFor target: XCUIElement? = nil, timeout: TimeInterval = 20) async throws -> Bool {
        let open = springboard.buttons["Open"].firstMatch
        guard let target else {
            try await helper.sim("openurl", url: url)
            if open.waitForExistence(timeout: 4) { open.tap() }
            return true
        }
        // The helper returns seconds after the link opened (it looks for the
        // sheet): watch for the target meanwhile, or a toast is gone.
        // Detached: a task on the main actor would wait for the poll below.
        let helper = helper!
        let opening = Task.detached { try await helper.sim("openurl", url: url) }
        let shown = waitUntil(timeout) {
            if open.exists { open.tap() }
            return target.exists
        }
        try await opening.value
        return shown
    }

    // MARK: - Waits

    func element(_ identifier: String, in root: XCUIApplication? = nil) -> XCUIElement {
        (root ?? app).descendants(matching: .any)[identifier].firstMatch
    }

    func require(_ element: XCUIElement, timeout: TimeInterval = 20, _ what: String) throws {
        guard element.waitForExistence(timeout: timeout) else {
            throw DevE2EError.flow("\(what) did not appear within \(Int(timeout)) s")
        }
    }

    func tap(_ element: XCUIElement, timeout: TimeInterval = 20, _ what: String) throws {
        try require(element, timeout: timeout, what)
        element.tap()
    }

    /// The index of the first of these to appear; nil when none did.
    func firstAppearing(_ elements: [XCUIElement], timeout: TimeInterval) -> Int? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let index = elements.firstIndex(where: \.exists) { return index }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < end
        return nil
    }

    /// Whether a tap on the element would land. `isHittable` alone records a
    /// failure ("Activation point invalid") for an element still sliding in
    /// off screen (an onboarding prompt right after sign-in, 2026-10-14).
    func canTap(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard !frame.isEmpty, app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return element.isHittable
    }

    /// Polls an on-screen condition; false when it did not hold in time.
    func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < end
        return false
    }

    /// Retries a backend read until it holds. A failed read is an error, never
    /// "not there yet": the helper throws and the test fails with it.
    func eventually<T>(_ what: String, timeout: TimeInterval = 30, _ probe: () async throws -> T?) async throws -> T {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if let value = try await probe() { return value }
            try await Task.sleep(for: .seconds(1))
        } while Date() < end
        throw DevE2EError.flow("\(what): not within \(Int(timeout)) s")
    }

    func settle(_ seconds: Double = 0.5) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// The scripted AI mock answers a request its rules miss with a text
    /// starting with this (backend `docs/E2E_AI_MOCK.md`): the scenario and
    /// its rule family drifted apart. Any such text fails the test.
    static let mockMissPrefix = "[scripted mock]"

    func requireNoMockMiss(_ text: String?, _ what: String) throws {
        if let text, text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(Self.mockMissPrefix) {
            throw DevE2EError.flow("\(what) is the AI mock's miss, not a scripted answer: \(text.prefix(200))")
        }
    }

    /// Every message `person` can read in `roomID` (the last `limit`), none of
    /// them a miss of the AI mock.
    func requireNoMockMiss(in roomID: String, as person: DevE2EFixture.Person, limit: Int = 30) async throws {
        let lines = try await helper.peer("read", person.localpart, roomID, String(limit))
        for line in lines {
            try requireNoMockMiss(line["body"] as? String, "a message in \(roomID)")
        }
    }

    func record(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = "backend"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The runner's helper on 127.0.0.1: the peer script, a fixed list of
/// read-only backend checks, Face ID and the running-app check. The test
/// itself needs no docker and holds no token but this run's.
struct DevE2EHelper {
    let baseURL: URL
    let token: String

    func ping() async throws {
        _ = try await call("ping", [:])
    }
    
    func mock(scenario: String) async throws {
        _ = try await call("mock", ["scenario": scenario])
    }

    /// `spiral-dev-peer.sh <args…>`; its JSON lines. A failure throws.
    @discardableResult
    func peer(_ args: String...) async throws -> [[String: Any]] {
        let reply = try await call("peer", ["args": args])
        return reply["lines"] as? [[String: Any]] ?? []
    }

    /// One of the helper's named read-only checks; its rows.
    func check(_ name: String, _ args: [String: String] = [:]) async throws -> [[String: String]] {
        let reply = try await call("check", ["name": name, "args": args])
        return reply["rows"] as? [[String: String]] ?? []
    }

    func sim(_ action: String, url: String? = nil) async throws {
        _ = try await call("sim", ["action": action, "url": url ?? ""])
    }

    private func call(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appending(path: "v1/\(endpoint)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DevE2EError.helper("\(endpoint) answered no JSON object")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, object["ok"] as? Bool == true else {
            throw DevE2EError.helper("\(endpoint) failed: \(object["error"] as? String ?? "no reason given")")
        }
        return object
    }
}
