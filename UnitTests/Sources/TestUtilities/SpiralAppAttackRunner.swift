//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (security pass 2, step 2): runs the post-sandbox attack
// corpus in the real host — a pooled `SpiralAppWebViewHost`, its scheme
// handler and CSP, the shell, and a real `SpiralAppPostSession` over a mocked
// room — and counts what got out.
//
// Three witnesses, none of which is the attack's own word alone:
//   1. the canary listener on the Mac (Tools/Scripts/spiral-post-canary.py):
//      every connection to 127.0.0.1:47913/47915, tcp or udp, is a hit (on a
//      device, the Mac's LAN address from `SPIRAL_CORPUS_CANARY_HOST`);
//   2. the native side: every bridge call and reply, every event the session
//      would have sent to the room, every expand, the fold after an echo;
//   3. the host: does the shell still answer, is it still the shell, what did
//      the scheme handler get asked for, what is on screen.
// The attack's report (`spike.report`, Debug only) adds what it saw inside the
// frame. Wired like `SpiralAppInstance` except that the bind also answers the
// report and no touch recorder is attached: a touch is simulated by calling
// `recordTouch()` for the attacks that say `@touch yes`.
//

import Foundation
@testable import Spiral
import SpiralAppShell
import UIKit
import WebKit

@MainActor
final class SpiralAppAttackRunner {
    // MARK: - The corpus

    struct Attack {
        let name: String
        let threat: String
        let expect: String
        let checklist: String
        let checks: Set<String>
        let wait: Duration
        let touch: Bool
        /// What a person's hand does while the post runs, in order (`@host`).
        let hostActions: [String]
        let manifestOverrides: [String: Any]
        let note: String
        let body: String

        init?(file: URL) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            var fields: [String: String] = [:]
            for line in text.split(separator: "\n") where line.hasPrefix("// @") {
                let entry = line.dropFirst(4)
                guard let space = entry.firstIndex(of: " ") else { continue }
                fields[String(entry[..<space])] = String(entry[entry.index(after: space)...])
            }
            guard let name = fields["attack"] else { return nil }
            self.name = name
            threat = fields["threat"] ?? ""
            expect = fields["expect"] ?? "blocked"
            checklist = fields["checklist"] ?? "—"
            checks = Set((fields["checks"] ?? "").split(separator: " ").map(String.init))
            wait = .milliseconds(Int(fields["wait"] ?? "") ?? 10000)
            touch = fields["touch"] == "yes"
            hostActions = (fields["host"] ?? "").split(separator: " ").map(String.init)
            manifestOverrides = fields["manifest"].flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
            note = fields["note"] ?? ""
            body = text
        }
    }

    static var corpusDirectory: URL? {
        Bundle(for: SpiralAppAttackRunner.self).url(forResource: "SpiralAppAttackCorpus", withExtension: nil)
    }

    static func loadCorpus() -> [Attack] {
        guard let directory = corpusDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "jsx" }
            .compactMap(Attack.init(file:))
            .sorted { $0.name < $1.name }
    }

    // MARK: - What a run produced

    struct Outcome: Encodable {
        var attack: String
        var threat: String
        var expect: String
        var checklist: String
        var note: String
        var verdict = "held"
        var why: [String] = []
        var report: [[String: String]] = []
        var reportArrived = false
        var mountError: String?
        var mountSeconds: Double = 0
        var canaryHits: [String] = []
        var bridgeCalls: [String] = []
        var sends: [String] = []
        var expands = 0
        var foldedState = ""
        var schemePaths: [String] = []
        var shell = ""
        var alive = true
        var neighbourAlive: Bool?
        var releaseSeconds: Double = 0
        var released = ""
        var recoveryMountSeconds: Double?
        var recoveryError: String?
        var snapshot: String?
        /// Device pass, real tap: how often the general pasteboard changed
        /// while the post ran, and any view controller presented over the host.
        var pasteboardChanges = 0
        /// The pasteboard's text after the run, for `pasteboard-not-hijacked`.
        var pasteboardText: String?
        var hostActions: [String] = []
        var presented: [String] = []
        var contentProcessDied = false
    }

    // MARK: - Wiring

    static let viewer = "@viewer:spiral.test"
    static let secondAccount = "@second:spiral.test"
    let marker = "SPIRAL-MARKER-\(UUID().uuidString.prefix(8))"
    private let outputDirectory: URL?
    private let window: UIWindow
    private let parent = UIViewController()
    private let pool = SpiralAppHostPool { SpiralAppWebViewHost(allowsSpikeProbe: true) }
    /// Keyed by the web view's content controller, held so its identifier is never reused.
    private var frameCatchers: [ObjectIdentifier: (controller: WKUserContentController, catcher: FrameCatcher)] = [:]
    private let prelude: String

    init() {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 360, height: 480)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        prelude = Self.corpusDirectory
            .flatMap { try? String(contentsOf: $0.appending(path: "_prelude.js"), encoding: .utf8) } ?? ""
        outputDirectory = ProcessInfo.processInfo.environment["SPIRAL_CORPUS_OUT"].map { URL(filePath: $0) }
    }

    func tearDown() {
        pool.drain()
        window.isHidden = true
    }

    /// One attack, one post, one host from the shared pool.
    struct Room {
        let proxy: JoinedRoomProxyMock
        let session: SpiralAppPostSession
        let activation = SpiralAppActivation()
    }

    func makeRoom(postID: String, account: String = viewer) async -> Room {
        let people: [RoomMemberProxyMock] = [
            .init(with: .init(userID: account, displayName: "Viewer", membership: .join)),
            .init(with: .init(userID: "@bob:spiral.test", displayName: "Bob", membership: .join)),
            .init(with: .init(userID: "@carol:spiral.test", displayName: "Carol \u{202E}lortnoc\u{202C}", membership: .join)),
            .init(with: .init(userID: "@assistant-x:spiral.test", displayName: "Assistant", membership: .join)),
            .init(with: .init(userID: "@left:spiral.test", displayName: "Gone", membership: .leave))
        ]
        let proxy = JoinedRoomProxyMock(.init(id: "!room:spiral.test", members: people, ownUserID: account))
        proxy.loadSpiralAppRelationsForReturnValue = .success([])
        proxy.sendSpiralRawEventTypeContentReturnValue = .success(())
        proxy.subscribeToSpiralEventsTypesListenerReturnValue = .failure(.eventNotFound)
        let session = SpiralAppPostSession(postEventID: postID, roomProxy: proxy, feed: SpiralAppActionFeed(roomProxy: proxy))
        await session.start()
        return Room(proxy: proxy, session: session)
    }

    // MARK: - Running

    /// A running attack: what `run` hands back so a caller can keep a post
    /// live while it mounts another (the concurrent reader).
    final class Live {
        let host: SpiralAppWebViewHost
        let room: Room
        var outcome: Outcome
        var report: [[String: String]]?
        var calls: [String] = []
        var expands = 0
        let start = ContinuousClock.now
        let canaryBefore: Int
        let pathsBefore: Int
        let pasteboardBefore = UIPasteboard.general.changeCount
        var presented: [String] = []
        /// The system killed this post's content process (jetsam on a device).
        var contentProcessDied = false
        var hostActions: Task<[String], Never>?

        init(host: SpiralAppWebViewHost, room: Room, outcome: Outcome, canaryBefore: Int, pathsBefore: Int) {
            self.host = host
            self.room = room
            self.outcome = outcome
            self.canaryBefore = canaryBefore
            self.pathsBefore = pathsBefore
        }
    }

    func run(_ attack: Attack, postID: String? = nil, room existing: Room? = nil) async -> Outcome {
        let live = await start(attack, postID: postID, room: existing)
        return await finish(live, attack: attack)
    }

    func start(_ attack: Attack, postID: String? = nil, room existing: Room? = nil, account: String = viewer) async -> Live {
        await Canary.mark("start \(attack.name)")
        let room = if let existing { existing } else { await makeRoom(postID: postID ?? "$post-\(attack.name)", account: account) }
        let host = pool.acquire() as! SpiralAppWebViewHost // swiftlint:disable:this force_cast
        host.containerView.frame = parent.view.bounds
        parent.view.addSubview(host.containerView)

        var outcome = Outcome(attack: attack.name, threat: attack.threat, expect: attack.expect,
                              checklist: attack.checklist, note: attack.note)
        let live = await Live(host: host, room: room, outcome: outcome,
                              canaryBefore: Canary.stats()?.total ?? -1,
                              pathsBefore: SpiralAppSchemeHandler.requestedPathsForTesting.count)

        room.session.onExpandRequested = { [weak live] in live?.expands += 1 }
        // As the registry does: a host whose process died is discarded, never
        // parked, or the pool hands the next post a web view that never paints.
        host.onContentProcessDied = { [weak live] in
            live?.contentProcessDied = true
            MXLog.info("[corpus] \(attack.name): the content process died")
        }
        host.bind { [weak live, weak session = room.session, activation = room.activation] method, args, _ in
            if method == SpiralAppCapability.spikeReport.rawValue {
                let body = (try? JSONSerialization.jsonObject(with: args) as? [String: Any]) ?? [:]
                live?.report = (body["results"] as? [[String: Any]] ?? []).map { $0.mapValues { "\($0)" } }
                return SpiralAppBridge.success(nil)
            }
            guard let session else { return SpiralAppBridge.failure(code: "gone", message: "gone") }
            let reply = await session.answer(method: method, args: args, activation: activation)
            live?.calls.append("\(method) \(String(decoding: args.prefix(160), as: UTF8.self)) → \(reply.prefix(160))")
            return reply
        }

        guard let artifact = pack(attack, markerInSource: !attack.checks.contains("no-marker")) else {
            outcome.mountError = "could not pack"
            live.outcome = outcome
            return live
        }
        if attack.touch { room.activation.recordTouch() }
        let frames = attack.hostActions.isEmpty ? nil : frameCatcher(for: host)
        frames?.postFrame = nil
        let mounting = ContinuousClock.now
        outcome.mountError = await Self.mount(host, SpiralAppMount(instanceID: postID ?? "$post-\(attack.name)", artifact: artifact,
                                                                   capabilities: SpiralAppCapability.production + [.spikeReport],
                                                                   viewerID: room.session.context["userId"] as? String ?? Self.viewer))
        outcome.mountSeconds = Self.seconds(mounting.duration(to: .now))
        live.outcome = outcome
        if let frames {
            live.hostActions = Task { await Self.perform(attack.hostActions, on: host, frames: frames) }
        }
        return live
    }

    /// Stand-ins for a person's hand on the simulator, which has no real tap:
    ///   - `gesture`: a script evaluated in the post's own frame, which WebKit
    ///     runs as a user gesture, dispatches `{spiralHostGesture}` there, so
    ///     the step runs inside it. Without the frame (not caught yet) the
    ///     shell posts the message into it instead, and WebKit carries only
    ///     its older gesture token with it, not `userActivation`. The attack
    ///     records `userActivation`, so a run says which it had.
    ///   - `copy`, `paste`: the edit menu's, in whichever frame has focus.
    /// One every 1.5 s, starting 1.5 s after the mount.
    private static func perform(_ actions: [String], on host: SpiralAppWebViewHost, frames: FrameCatcher) async -> [String] {
        var done: [String] = []
        for (index, action) in actions.enumerated() {
            try? await Task.sleep(for: .milliseconds(1500))
            switch action {
            case "gesture":
                if let frame = frames.postFrame, let view = webView(of: host) {
                    let answer = await evaluate(view, in: frame, """
                    window.dispatchEvent(new MessageEvent('message', { data: { spiralHostGesture: \(index) } })); 'dispatched'
                    """)
                    done.append("gesture in the post's frame: \(answer)")
                } else {
                    let answer = await evaluate(host, """
                    (function () {
                      var frame = document.querySelector('iframe');
                      if (!frame || !frame.contentWindow) return 'no frame';
                      frame.contentWindow.postMessage({ spiralHostGesture: \(index) }, '*');
                      return 'sent';
                    })()
                    """)
                    done.append("gesture from the shell: \(answer ?? "no answer")")
                }
            case "copy", "paste":
                let view = webView(of: host)
                let edit = action == "copy" ? #selector(UIResponderStandardEditActions.copy(_:)) : #selector(UIResponderStandardEditActions.paste(_:))
                view?.perform(edit, with: nil)
                done.append("\(action): \(view == nil ? "no web view" : "sent")")
            default:
                done.append("\(action): unknown")
            }
        }
        return done
    }

    /// A frame's answer to a script, run as a user gesture as every
    /// `evaluateJavaScript` is.
    private static func evaluate(_ webView: WKWebView, in frame: WKFrameInfo, _ script: String) async -> String {
        final class Box {
            var value = "no answer"
            var done = false
        }
        let box = Box()
        webView.evaluateJavaScript(script, in: frame, in: .page) { result in
            switch result {
            case .success(let value): box.value = "\(value)"
            case .failure(let error): box.value = "error: \(error.localizedDescription)"
            }
            box.done = true
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while !box.done, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return box.value
    }

    /// Catches the post's frame for `gesture`: a script in a world of its own
    /// reports every frame's load to a handler in that world, and the last
    /// frame that is not the shell is the post's.
    @MainActor
    final class FrameCatcher: NSObject, WKScriptMessageHandler {
        static let name = "spiralCorpusFrame"
        static let world = WKContentWorld.world(name: "SpiralCorpusFrames")
        var postFrame: WKFrameInfo?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if !message.frameInfo.isMainFrame { postFrame = message.frameInfo }
        }
    }

    private func frameCatcher(for host: SpiralAppWebViewHost) -> FrameCatcher? {
        guard let controller = Self.webView(of: host)?.configuration.userContentController else { return nil }
        if let entry = frameCatchers[ObjectIdentifier(controller)] { return entry.catcher }
        let catcher = FrameCatcher()
        controller.add(catcher, contentWorld: FrameCatcher.world, name: FrameCatcher.name)
        controller.addUserScript(WKUserScript(source: "window.webkit.messageHandlers.\(FrameCatcher.name).postMessage(1);",
                                              injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: FrameCatcher.world))
        frameCatchers[ObjectIdentifier(controller)] = (controller, catcher)
        return catcher
    }

    /// The host's own mount, given up on after 30 s so one post that never
    /// answers cannot stop the corpus. A mount still waiting then is a finding.
    private static func mount(_ host: SpiralAppWebViewHost, _ mount: SpiralAppMount) async -> String? {
        final class Box {
            var error: String?
            var done = false
        }
        let box = Box()
        Task {
            do {
                try await host.mount(mount)
            } catch {
                box.error = String(describing: error).prefix(200).description
            }
            box.done = true
        }
        let deadline = ContinuousClock.now + .seconds(30)
        while !box.done, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return box.done ? box.error : "mount() had not returned after 30 s"
    }

    func finish(_ live: Live, attack: Attack, keepHost: Bool = false) async -> Outcome {
        // The report, or the attack's patience.
        let deadline = live.start + attack.wait
        while live.report == nil, ContinuousClock.now < deadline {
            notePresented(live)
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Requests in flight when the report left still get to land.
        try? await Task.sleep(for: .seconds(2))
        await observe(live, attack: attack)
        if !keepHost { await release(live) }
        await echo(live)
        await judge(live, attack: attack)
        await Canary.mark("end \(attack.name) \(live.outcome.verdict)")
        return live.outcome
    }

    /// A share sheet or any other controller WebKit put over the host.
    private func notePresented(_ live: Live) {
        guard let presented = parent.presentedViewController ?? window.rootViewController?.presentedViewController else { return }
        let name = String(describing: type(of: presented))
        if !live.presented.contains(name) {
            live.presented.append(name)
            MXLog.info("[corpus] \(live.outcome.attack) presented \(name)")
        }
    }

    /// The host and the shell, after the attack.
    private func observe(_ live: Live, attack: Attack) async {
        notePresented(live)
        var outcome = live.outcome
        outcome.hostActions = await live.hostActions?.value ?? []
        outcome.pasteboardChanges = UIPasteboard.general.changeCount - live.pasteboardBefore
        if attack.checks.contains("pasteboard-not-hijacked") {
            outcome.pasteboardText = UIPasteboard.general.string.map { String($0.prefix(200)) }
        }
        outcome.contentProcessDied = live.contentProcessDied
        outcome.presented = live.presented
        outcome.reportArrived = live.report != nil
        outcome.report = live.report ?? []
        outcome.bridgeCalls = live.calls
        outcome.expands = live.expands
        outcome.alive = await live.host.waitForPaint()
        outcome.shell = await Self.evaluate(live.host, "JSON.stringify({href: location.href, shell: typeof window.__spiralShell, frames: document.querySelectorAll('iframe').length})") ?? "no answer"
        let paths = SpiralAppSchemeHandler.requestedPathsForTesting
        outcome.schemePaths = Array(paths.dropFirst(min(live.pathsBefore, paths.count)))
        if attack.checks.contains("snapshot") || attack.checks.contains("spin") {
            outcome.snapshot = await snapshot(live.host, name: attack.name)
        }
        if let stats = await Canary.stats(), live.canaryBefore >= 0 {
            outcome.canaryHits = stats.hits.dropFirst(live.canaryBefore).map { "\($0.kind):\($0.port) \($0.line)" }
        }
        live.outcome = outcome
    }

    func release(_ live: Live) async {
        let releasing = ContinuousClock.now
        if live.contentProcessDied {
            live.host.onContentProcessDied = nil
            live.host.containerView.removeFromSuperview()
            live.host.destroy()
            live.outcome.releaseSeconds = Self.seconds(releasing.duration(to: .now))
            live.outcome.released = "discarded: the content process died"
            return
        }
        let result = await pool.release(live.host)
        live.outcome.releaseSeconds = Self.seconds(releasing.duration(to: .now))
        live.outcome.released = "\(result)"
    }

    /// What the room would have received, and the fold once it comes back.
    private func echo(_ live: Live) async {
        let sends = live.room.proxy.sendSpiralRawEventTypeContentReceivedInvocations.map(\.content)
        live.outcome.sends = sends.map { String($0.prefix(1200)) }
        let events = sends.enumerated().compactMap { index, content -> String? in
            guard let object = try? JSONSerialization.jsonObject(with: Data(content.utf8)) else { return nil }
            let event: [String: Any] = ["type": SpiralAppAction.eventType, "event_id": "$echo-\(live.outcome.attack)-\(index)",
                                        "sender": live.room.proxy.ownUserID, "origin_server_ts": 1000 + index, "content": object]
            return (try? JSONSerialization.data(withJSONObject: event)).map { String(decoding: $0, as: UTF8.self) }
        }
        if !events.isEmpty {
            await live.room.session.ingestForTesting(events)
        }
        let state = live.room.session.snapshot.state.jsonObject
        live.outcome.foldedState = (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]))
            .map { String(decoding: $0.prefix(1500), as: UTF8.self) } ?? ""
    }

    // MARK: - Verdicts

    private func judge(_ live: Live, attack: Attack) async {
        var outcome = live.outcome
        let always = [Self.canaryRule, Self.reachedRule, Self.shellRule, Self.compileRule]
        let escaped = (always.compactMap { $0(outcome, attack, live) }
            + attack.checks.compactMap { Self.checkRules[$0] }.compactMap { $0(outcome, live, marker) })
        let concerns = Self.concerns(outcome, attack: attack)

        if !escaped.isEmpty {
            outcome.verdict = "ESCAPED"
        } else if attack.expect == "contained" || !concerns.isEmpty {
            outcome.verdict = "observed"
        } else if attack.expect == "by-design" {
            outcome.verdict = "by design"
        }
        outcome.why = escaped + concerns
        live.outcome = outcome
    }

    private typealias Rule = (Outcome, Attack, Live) -> String?
    private typealias CheckRule = (Outcome, Live, String) -> String?

    private static let canaryRule: Rule = { outcome, _, _ in
        outcome.canaryHits.isEmpty ? nil : "canary hit: \(outcome.canaryHits.joined(separator: "; "))"
    }

    private static let reachedRule: Rule = { outcome, attack, _ in
        let reached = outcome.report.filter { $0["outcome"] == "REACHED" }
        guard !reached.isEmpty, ["blocked", "refused"].contains(attack.expect) else { return nil }
        return "reached in the frame: " + reached.map { $0["check"] ?? "" }.joined(separator: ", ")
    }

    private static let shellRule: Rule = { outcome, _, _ in
        let intact = outcome.shell.contains("spiral-app://shell") && outcome.shell.contains("\"shell\":\"object\"")
        return intact || !outcome.alive || outcome.contentProcessDied ? nil : "the shell document was replaced: \(outcome.shell)"
    }

    private static let compileRule: Rule = { outcome, attack, _ in
        attack.expect == "compile-refused" && outcome.reportArrived ? "compiled and ran" : nil
    }

    /// The `@checks` an attack names, each a way it would have got out.
    private static let checkRules: [String: CheckRule] = [
        "no-mentions": { outcome, _, _ in
            let mentions = outcome.sends.compactMap(mentions).filter { !$0.isEmpty }
            return mentions.isEmpty ? nil : "a ping went out with no touch: \(mentions)"
        },
        "mentions-members-only": { outcome, _, _ in
            let people: Set = ["@bob:spiral.test", "@carol:spiral.test"]
            let strangers = outcome.sends.compactMap(mentions).flatMap { $0 }.filter { !people.contains($0) }
            return strangers.isEmpty ? nil : "pinged someone who is not a person in the room: \(strangers)"
        },
        "no-pasteboard": { outcome, _, _ in
            outcome.pasteboardChanges > 0 ? "the pasteboard changed \(outcome.pasteboardChanges)×" : nil
        },
        "pasteboard-not-hijacked": { outcome, _, _ in
            outcome.pasteboardText?.contains("hijacked") == true ? "the copy landed as \(outcome.pasteboardText ?? "")" : nil
        },
        "no-expand": { outcome, _, _ in outcome.expands > 0 ? "took the screen \(outcome.expands)× with no touch" : nil },
        "max-expand-1": { outcome, _, _ in outcome.expands > 1 ? "took the screen \(outcome.expands)× for one touch" : nil },
        "no-sends": { outcome, _, _ in outcome.sends.isEmpty ? nil : "\(outcome.sends.count) events reached the room" },
        "max-sends-25": { outcome, _, _ in outcome.sends.count > 25 ? "\(outcome.sends.count) untouched writes in 4 s" : nil },
        "max-content-32768": { outcome, _, _ in
            outcome.sends.contains { $0.utf8.count > 32768 } ? "an action over 32 KB was sent" : nil
        },
        "no-marker": { outcome, _, marker in
            let seen = (outcome.report.map { $0["detail"] ?? "" } + outcome.bridgeCalls).joined()
            return seen.contains(marker) || seen.contains("MARKER-WRITER") ? "found the writer's marker" : nil
        },
        "mount-refused": { outcome, _, _ in
            outcome.mountError == nil ? "mounted although the manifest names a runtime this build does not carry" : nil
        },
        "boot-hang": { outcome, _, _ in
            outcome.mountError?.contains("had not returned") == true ? "mount() never returned: the row would hang for good" : nil
        },
        "clean-lines": { outcome, _, _ in
            let dirty = outcome.sends.flatMap(summaryLines).filter { line in
                line.localizedCaseInsensitiveContains("@room") || line.unicodeScalars.contains {
                    [.control, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
                        || SpiralAppActionLimits.hiddenScalars.contains($0.value)
                }
            }
            return dirty.isEmpty ? nil : "summary lines sent with control, bidi or hidden characters or @room: \(dirty.map(\.debugDescription))"
        },
        "owned-intact": { outcome, live, _ in
            guard let state = try? JSONSerialization.jsonObject(with: Data(outcome.foldedState.utf8)) as? [String: Any],
                  let namespace = state[SpiralAppOperation.ownedNamespace] else { return nil }
            guard let owned = namespace as? [String: Any] else { return "the owned namespace was replaced by a shared write" }
            let foreign = owned.keys.filter { $0 != live.room.proxy.ownUserID }
            return foreign.isEmpty ? nil : "the fold shows by.\(foreign.joined(separator: ",")) written by \(live.room.proxy.ownUserID)"
        }
    ]

    private static func concerns(_ outcome: Outcome, attack: Attack) -> [String] {
        var concerns: [String] = []
        if outcome.contentProcessDied { concerns.append("the system killed the post's content process; the host was discarded") }
        let allowed: Set = ["/index.html", "/runtime/v1/bootstrap.js", "/runtime/v1/react.js", "/runtime/v1/sdk.js",
                            "/runtime/v1/ui.js", "/runtime/v1/ui.css", "/runtime/v1/play.js", "/runtime/v1/compile.js", "/app.jsx"]
        let odd = outcome.schemePaths.filter { !allowed.contains($0) }
        // Without the person's Copy landing, "not hijacked" proves nothing.
        if attack.checks.contains("pasteboard-not-hijacked"), outcome.pasteboardText?.contains("SPIRAL-COPY-TEXT") != true {
            concerns.append("the Copy did not put the post's selected text on the pasteboard: \(outcome.pasteboardText ?? "nil")")
        }
        if attack.checks.contains("scheme-paths"), !odd.isEmpty { concerns.append("asked the scheme handler for \(odd)") }
        if let error = outcome.mountError, !["contained", "compile-refused"].contains(attack.expect), !attack.checks.contains("mount-refused") {
            concerns.append("mount: \(error)")
        }
        // A mount refused before it began leaves nothing to answer.
        if !outcome.alive, !attack.checks.contains("mount-refused") { concerns.append("the shell stopped answering") }
        return concerns
    }

    /// Every `summary.line` an action carried, one per language.
    private nonisolated static func summaryLines(_ content: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
              let line = (object["summary"] as? [String: Any])?["line"] else { return [] }
        if let line = line as? String { return [line] }
        return (line as? [String: Any])?.values.compactMap { $0 as? String } ?? []
    }

    private nonisolated static func mentions(_ content: String) -> [String]? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] else { return nil }
        return (object["m.mentions"] as? [String: Any])?["user_ids"] as? [String] ?? []
    }

    // MARK: - Packing

    func pack(_ attack: Attack, markerInSource: Bool = true) -> SpiralAppArtifact? {
        var manifest: [String: Any] = ["app_id": attack.name, "runtime": "1", "entry": "app.jsx", "aspect": "3:4",
                                       "capabilities": (SpiralAppCapability.production + [.spikeReport]).map(\.rawValue)]
        for (key, value) in attack.manifestOverrides {
            manifest[key] = value
        }
        let source = Canary.aimed(prelude + "\n" + attack.body)
            .replacingOccurrences(of: "__ATTACK_ID__", with: attack.name)
            .replacingOccurrences(of: "__MARKER__", with: markerInSource ? marker : "none")
        guard let manifestData = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]) else { return nil }
        let sourceData = Data(source.utf8)
        var bytes = Data("SPIRALv1\n".utf8)
        bytes.append(Data("manifest.json\n\(manifestData.count)\n".utf8))
        bytes.append(manifestData)
        bytes.append(Data("app.jsx\n\(sourceData.count)\n".utf8))
        bytes.append(sourceData)
        return SpiralAppArtifact.verified(packed: bytes, claimedDigest: SpiralAppArtifact.digest(of: bytes))
    }

    // MARK: - Probes of the host

    static func webView(of host: SpiralAppWebViewHost) -> WKWebView? {
        host.containerView.subviews.compactMap { $0 as? WKWebView }.first
    }

    /// The main frame's answer, or nil if it gives none in two seconds.
    static func evaluate(_ host: SpiralAppWebViewHost, _ script: String) async -> String? {
        guard let webView = webView(of: host) else { return nil }
        final class Box {
            var value: String?
            var done = false
        }
        let box = Box()
        webView.evaluateJavaScript(script) { value, error in
            box.value = (value as? String) ?? error.map { "error: \($0.localizedDescription)" }
            box.done = true
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while !box.done, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return box.value
    }

    private func snapshot(_ host: SpiralAppWebViewHost, name: String) async -> String {
        final class Box {
            var image: UIImage?
            var done = false
        }
        let box = Box()
        host.takeSnapshot { box.image = $0
            box.done = true
        }
        while !box.done {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let image = box.image, let data = image.pngData() else { return "no picture" }
        if let outputDirectory {
            try? data.write(to: outputDirectory.appending(path: "snapshot-\(name).png"))
        }
        return "picture \(Int(image.size.width))x\(Int(image.size.height))"
    }

    /// A benign post on another host, for the attacks that may take more than their own.
    func neighbour() async -> SpiralAppWebViewHost? {
        let benign = "export default () => <div>neighbour</div>;"
        guard let attack = Attack(name: "control-neighbour", body: benign), let artifact = pack(attack) else { return nil }
        let host = SpiralAppWebViewHost(allowsSpikeProbe: true)
        host.containerView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        parent.view.addSubview(host.containerView)
        host.bind { _, _, _ in SpiralAppBridge.success(nil) }
        try? await host.mount(SpiralAppMount(instanceID: "neighbour", artifact: artifact, capabilities: []))
        return host
    }

    /// How long a fresh post takes to mount after an attack, or why it could not.
    func recovery() async -> (Double?, String?) {
        guard let attack = Attack(name: "control-recovery", body: "export default () => <div>recovered</div>;"),
              let artifact = pack(attack) else { return (nil, "pack") }
        let host = pool.acquire() as! SpiralAppWebViewHost // swiftlint:disable:this force_cast
        host.containerView.frame = parent.view.bounds
        parent.view.addSubview(host.containerView)
        host.bind { _, _, _ in SpiralAppBridge.success(nil) }
        let start = ContinuousClock.now
        defer { Task { [pool] in await pool.release(host) } }
        do {
            try await host.mount(SpiralAppMount(instanceID: "recovery", artifact: artifact, capabilities: []))
            return (Self.seconds(start.duration(to: .now)), nil)
        } catch {
            return (Self.seconds(start.duration(to: .now)), String(describing: error).prefix(160).description)
        }
    }

    func write(_ outcomes: [Outcome], name: String) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(outcomes) else { return }
        if let outputDirectory {
            try? data.write(to: outputDirectory.appending(path: "\(name).json"))
        }
        await Canary.post(data, name: name)
    }

    /// Swap in use, in GB. A simulator shares the Mac's kernel, so this is
    /// the Mac's: what a post that allocates without end eventually fills.
    nonisolated static func swapUsedGigabytes() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return nil }
        return Double(usage.xsu_used) / 1_073_741_824
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

extension SpiralAppAttackRunner.Attack {
    /// A control post written inline: no headers, no report expected.
    init?(name: String, body: String) {
        self.name = name
        threat = "control"
        expect = "control"
        checklist = "—"
        checks = []
        wait = .seconds(3)
        touch = false
        hostActions = []
        manifestOverrides = [:]
        note = ""
        self.body = body
    }
}

/// The control port of the canary listener. Not a canary itself.
enum Canary {
    struct Hit: Decodable {
        let t: Double
        let kind: String
        let port: Int
        let line: String
    }

    struct Stats: Decodable {
        let total: Int
        let hits: [Hit]
    }

    /// Where the canary listens: the Mac's loopback for a simulator, which
    /// shares the Mac's network stack; the Mac's LAN address for a device.
    nonisolated static let host = ProcessInfo.processInfo.environment["SPIRAL_CORPUS_CANARY_HOST"] ?? "127.0.0.1"

    /// An attack or a control aimed at the canary: on a device, every
    /// `127.0.0.1` becomes the Mac's address, and a chosen `<label>.localhost`
    /// name becomes `<label>.example.com`, so a lookup of it would have to
    /// leave the phone, where the packet capture sees it.
    nonisolated static func aimed(_ source: String) -> String {
        guard host != "127.0.0.1" else { return source }
        return source.replacingOccurrences(of: "127.0.0.1", with: host)
            .replacingOccurrences(of: #"([A-Za-z0-9-]+)\.localhost"#, with: "$1.example.com", options: .regularExpression)
    }

    private static let control = URL(string: "http://\(host):47914")!

    static func stats() async -> Stats? {
        guard let (data, _) = try? await URLSession.shared.data(from: control.appending(path: "stats")) else { return nil }
        return try? JSONDecoder().decode(Stats.self, from: data)
    }

    static func mark(_ text: String) async {
        let safe = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "mark"
        _ = try? await URLSession.shared.data(from: URL(string: "\(control.absoluteString)/mark?\(safe)")!)
    }

    static func post(_ data: Data, name: String) async {
        var request = URLRequest(url: control.appending(path: name))
        request.httpMethod = "POST"
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }
}
