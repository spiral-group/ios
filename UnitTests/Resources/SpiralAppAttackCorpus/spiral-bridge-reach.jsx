// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-bridge-reach
// @threat escape
// @expect blocked
// @checklist —
// @checks no-sends

export default () => <Done after={2000} run={async () => {

  exists("window.webkit", window.webkit);
  exists("webkit.messageHandlers.spiralAppRequest", window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.spiralAppRequest);
  exists("webkit.messageHandlers.spiralAppConsole", window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.spiralAppConsole);
  exists("window.__spiralShell", window.__spiralShell);
  await probe("parent.__spiralShell", async () => ({ reached: !!parent.__spiralShell }));
  await probe("parent.document", async () => ({ reached: !!parent.document, detail: parent.document && parent.document.title }));
  await probe("top.document event to the relay", async () => { top.document.dispatchEvent(new CustomEvent("spiral-host-request", { detail: { id: "x", body: { method: "state.shared.write", args: "{}", userActivation: true } } })); return { reached: true }; });
  await probe("own document event named like the relay", async () => {
    let answered = false; document.addEventListener("spiral-host-reply", () => { answered = true; });
    document.dispatchEvent(new CustomEvent("spiral-host-request", { detail: { id: "y", body: { method: "app.context.read", args: "null", userActivation: false } } }));
    await settle(500); return { reached: answered }; });
  await probe("window.frameElement", async () => ({ reached: !!window.frameElement }));
  await probe("parent.frames[0] is me", async () => ({ info: true, detail: String(parent.frames.length) }));
}} />;
