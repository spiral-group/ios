// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-websocket
// @threat network
// @expect blocked
// @checklist api-websocket

export default () => <Done after={2000} run={async () => {

  exists("WebSocket constructor", globalThis.WebSocket);
  await probe("new WebSocket", () => new Promise((resolve, reject) => {
    const s = new WebSocket(CANARY_WS); s.onopen = () => resolve({ reached: true }); s.onerror = () => reject(new Error("onerror")); setTimeout(() => reject(new Error("no open")), 1500); }));
  await probe("WebSocket via prototype of a fresh object", async () => {
    const ctor = Object.getPrototypeOf(document).constructor.constructor("return WebSocket")();
    return { reached: !!ctor, detail: String(ctor) }; });
}} />;
