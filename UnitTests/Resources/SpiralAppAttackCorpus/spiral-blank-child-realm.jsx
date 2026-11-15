// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-blank-child-realm
// @threat network
// @expect blocked
// @checklist —
// @wait 12000
// @note A src-less iframe: an about:blank child, no navigation (no policy asked), not governed by frame-src. Reached from the parent the moment it is appended: is it the same origin, did the host's scripts run in its first document, and do its WebRTC and link methods get out?

export default () => <Done after={5000} run={async () => {
  const f = document.createElement("iframe");
  document.body.appendChild(f);
  let w = null;
  await probe("contentWindow of a src-less child", () => { w = f.contentWindow; return { info: true, detail: w ? "a window" : "null" }; });
  await probe("same origin as the post", () => ({ reached: !!(w && w.document), detail: String(w && w.location && w.location.href) }));
  if (!w) return;
  await probe("host scripts ran in the child", () => {
    const click = Object.getOwnPropertyDescriptor(w.HTMLElement.prototype, "click");
    return { info: true, detail: `click locked: ${click && click.configurable === false}; RTCPeerConnection: ${typeof w.RTCPeerConnection}` };
  });
  await probe("child RTCPeerConnection", async () => {
    const pc = new w.RTCPeerConnection({ iceServers: [{ urls: "stun:127.0.0.1:47913" }] });
    pc.createDataChannel("x"); await pc.setLocalDescription(await pc.createOffer());
    return { reached: true, detail: "offer set" };
  });
  const link = (path) => { const a = document.createElement("a"); a.href = CANARY + "/" + path; a.target = "_blank"; return a; };
  await attempt("child dispatchEvent on a detached link", () => w.EventTarget.prototype.dispatchEvent.call(link("child-dispatch"), new MouseEvent("click")));
  await attempt("child click() on a detached link", () => w.HTMLElement.prototype.click.call(link("child-click")));
  await attempt("child document's own link", () => { const a = w.document.createElement("a"); a.href = CANARY + "/child-own"; a.target = "_blank"; a.click(); });
  await settle(3000);
}} />;
