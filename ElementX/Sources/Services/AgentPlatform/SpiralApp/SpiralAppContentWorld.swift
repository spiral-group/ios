//
// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// AGENT-PLATFORM (Brief 0066, ADR-0007): keeping the native bridge out of
// reach of untrusted code.
//
// The problem, confirmed by the Brief 0066 probe rather than assumed: a
// script message handler is defined "in all frames in the specified content
// world" (Apple's `addScriptMessageHandler(_:contentWorld:name:)` docs), so
// a sandboxed, opaque-origin subframe sees `window.webkit.messageHandlers`
// exactly like the main frame does. OWASP MASTG and the WebKit pentest
// literature both call this out: an untrusted iframe "becomes a native-code
// pivot" unless the handler checks `frameInfo` and rejects unexpected
// subframes.
//
// So there are two independent controls, and both are kept:
//
//   1. The handler lives in a NAMED content world. Page-world JavaScript —
//      which is where an artifact runs — has no `window.webkit` for it at
//      all, because worlds do not share globals.
//   2. The handler still verifies `frameInfo.isMainFrame` and refuses
//      anything else. This is the control OWASP asks for, and it holds even
//      if a future change moves the handler back to the page world.
//
// The shell runs in the page world (it is ordinary bundled JavaScript), so
// it cannot call into the isolated world directly. They share the DOM, which
// is the sanctioned bridge: a `CustomEvent` carries a request across, and a
// second one carries the reply back. The relay script that does this is
// injected `forMainFrameOnly: true`, so it does not exist inside an
// artifact's frame either.
//

import Foundation
import WebKit

enum SpiralAppContentWorld {
    /// Isolated world holding every native handler.
    ///
    /// Not `.page`: that is where artifact code runs.
    static let host = WKContentWorld.world(name: "spiral-app-host")

    /// Event the page-world shell dispatches to make a request.
    static let requestEvent = "spiral-host-request"
    /// Event the relay dispatches with the reply.
    static let replyEvent = "spiral-host-reply"

    /// Runs in ``host``, main frame only. Carries requests across the world
    /// boundary and nothing else — it exposes no native object to the page.
    static var relayScript: String {
        """
        (function () {
          document.addEventListener("\(requestEvent)", function (event) {
            var detail = event.detail || {};
            var id = detail.id;
            var reply = function (payload) {
              document.dispatchEvent(new CustomEvent("\(replyEvent)", {
                detail: { id: id, payload: payload }
              }));
            };
        
            if (detail.channel === "console") {
              try {
                window.webkit.messageHandlers.\(SpiralAppConsoleRelay.handlerName)
                  .postMessage(detail.body);
              } catch (e) { /* host went away */ }
              return;
            }
        
            try {
              window.webkit.messageHandlers.\(SpiralAppBridge.handlerName)
                .postMessage(detail.body)
                .then(reply)
                .catch(function (e) {
                  reply(JSON.stringify({
                    ok: false, code: "unavailable", message: String(e)
                  }));
                });
            } catch (e) {
              reply(JSON.stringify({
                ok: false, code: "unavailable", message: String(e)
              }));
            }
          });
        })();
        """
    }
}
