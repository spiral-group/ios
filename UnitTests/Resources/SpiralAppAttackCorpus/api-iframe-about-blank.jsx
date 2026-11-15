// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-iframe-about-blank
// @threat escape
// @expect blocked
// @checklist api-iframe-about-blank

export default () => <Done after={2000} run={async () => {

  const f = make("iframe", { src: "about:blank" }); await settle(300);
  await probe("about:blank frame realm", async () => { const w = f.contentWindow; const ok = !!(w && w.RTCPeerConnection); return { reached: ok, detail: w ? "window object" : "none" }; });
  await probe("about:blank frame fetch", async () => { await f.contentWindow.fetch(CANARY + "/blank-fetch"); return { reached: true }; });
}} />;
