// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-webrtc-child-realm
// @threat network
// @expect blocked
// @checklist —
// @wait 14000
// @note harden.ts strips WebRTC from the post's document only. A child frame — srcdoc, data:, a blob script inside srcdoc — would be a fresh realm: STUN at the canary's UDP port, TURN over TCP at the other. CSP has no WebRTC directive, and the proxy does not carry it.

const RTC_CHILD = `(async function () {
  var r = { where: String(location.href).slice(0, 24), has: typeof RTCPeerConnection };
  try {
    var pc = new RTCPeerConnection({ iceServers: [{ urls: "stun:127.0.0.1:47913" },
      { urls: "turn:127.0.0.1:47915?transport=tcp", username: "u", credential: "p" }] });
    pc.createDataChannel("x");
    var offer = await pc.createOffer(); await pc.setLocalDescription(offer);
    await new Promise(function (done) { setTimeout(done, 3000); });
    r.ice = pc.iceGatheringState;
  } catch (e) { r.error = String(e).slice(0, 120); }
  parent.postMessage({ rtcReport: r }, "*");
})();`;

export default () => <Done after={5000} run={async () => {
  const reports = [];
  window.addEventListener("message", (event) => { if (event.data && event.data.rtcReport) reports.push(event.data.rtcReport); });
  const frame = (label, setup) => {
    try { const f = document.createElement("iframe"); setup(f); document.body.appendChild(f); note(label, "info", "frame inserted"); }
    catch (e) { note(label, "blocked", describe(e)); }
  };
  frame("srcdoc, inline script", (f) => { f.srcdoc = `<script>${RTC_CHILD}</script>`; });
  const blob = URL.createObjectURL(new Blob([RTC_CHILD], { type: "text/javascript" }));
  frame("srcdoc, blob script", (f) => { f.srcdoc = `<script src="${blob}"></script>`; });
  frame("srcdoc, blob module", (f) => { f.srcdoc = `<script type="module" src="${blob}"></script>`; });
  frame("data: document", (f) => { f.src = "data:text/html," + encodeURIComponent(`<script>${RTC_CHILD}</script>`); });
  await settle(7000);
  if (reports.length === 0) note("child realms", "blocked", "no child frame ran a script");
  for (const r of reports) note(`child ${r.where}`, r.has === "function" ? "REACHED" : "blocked", JSON.stringify(r));
}} />;
