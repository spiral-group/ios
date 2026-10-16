//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007 § 4.2): the native end of the shell's
// bridge.
//
// Shape reused verbatim from the retired Element Call bridge
// (`attic/element-call/src/spiral/bridge.ts`): a reply-style handler whose
// `postMessage` returns a Promise, answering with `{ok:true,data}` or
// `{ok:false,code,message}` over a small closed set of codes. The team
// already reads those codes, and `conflict` already means what a state
// collision means here.
//
// The untrusted app never reaches this. It lives in a sandboxed
// opaque-origin subframe with no `window.webkit`; only the shell — the main
// frame — can call, and `isMainFrame` is checked on every message rather
// than assumed.
//

import Foundation
import WebKit

/// Answers one method call from the shell.
///
/// Returns the JSON string the shell will parse. Implementations must not
/// throw: a refusal is a value, not an error, so a hostile caller cannot
/// distinguish "denied" from "crashed".
typealias SpiralAppMethodHandler = @MainActor (String, Data, Bool) async -> String

final class SpiralAppBridge: NSObject, WKScriptMessageHandlerWithReply {
    /// Handler name, reachable only from ``SpiralAppContentWorld/host``.
    static let handlerName = "spiralAppRequest"

    private let handler: SpiralAppMethodHandler

    init(handler: @escaping SpiralAppMethodHandler) {
        self.handler = handler
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
        // The shell is the main frame; the app is a subframe. A call from
        // anywhere else means the two-document design has been broken, and
        // the only safe response is to refuse and say so loudly.
        guard message.frameInfo.isMainFrame else {
            MXLog.error("[SpiralApp] bridge call from a subframe — refusing")
            replyHandler(Self.failure(code: "rejected", message: "not callable from this frame"), nil)
            return
        }

        guard message.name == Self.handlerName,
              let body = message.body as? [String: Any],
              let method = body["method"] as? String,
              let argsJSON = body["args"] as? String else {
            replyHandler(Self.failure(code: "rejected", message: "malformed request"), nil)
            return
        }

        let userActivation = body["userActivation"] as? Bool ?? false
        let argsData = Data(argsJSON.utf8)

        Task { @MainActor in
            let reply = await handler(method, argsData, userActivation)
            replyHandler(reply, nil)
        }
    }

    // MARK: - Envelope

    static func success(_ value: Any?) -> String {
        let payload: [String: Any] = ["ok": true, "data": value ?? NSNull()]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return failure(code: "unavailable", message: "could not encode the reply")
        }
        return json
    }

    /// - Parameter code: one of `conflict`, `gone`, `rejected`, `unavailable`.
    ///   Anything else is coerced to `unavailable` by the shell.
    static func failure(code: String, message: String) -> String {
        let payload: [String: Any] = ["ok": false, "code": code, "message": message]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return #"{"ok":false,"code":"unavailable","message":"encoding failed"}"#
        }
        return json
    }
}
