// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-iframe-contentwindow
// @threat escape
// @expect blocked
// @checklist api-iframe-contentwindow

export default () => <Done after={2000} run={async () => {

  const f = document.createElement("iframe"); document.body.appendChild(f); await settle(300);
  await probe("fresh realm RTCPeerConnection", async () => { const C = f.contentWindow && f.contentWindow.RTCPeerConnection; return { reached: typeof C === "function" }; });
  await probe("fresh realm WebSocket", async () => { const W = f.contentWindow.WebSocket; new W(CANARY_WS + "/frame"); return { reached: true }; });
  await probe("fresh realm sendBeacon", async () => ({ reached: f.contentWindow.navigator.sendBeacon(CANARY + "/frame-beacon", "x") }));
}} />;
