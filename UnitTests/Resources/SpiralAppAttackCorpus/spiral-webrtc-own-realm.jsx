// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-webrtc-own-realm
// @threat network
// @expect blocked
// @checklist —
// @wait 9000
// @note WebRTC in the post's own realm, every name and the ways back to a constructor: STUN at the canary's UDP port, TURN over TCP.

export default () => <Done after={4000} run={async () => {
  for (const name of ["RTCPeerConnection", "webkitRTCPeerConnection", "RTCDataChannel", "RTCRtpTransceiver", "RTCIceCandidate", "RTCSessionDescription"]) {
    exists(name, globalThis[name]);
  }
  await probe("redefine RTCPeerConnection", () => {
    Object.defineProperty(globalThis, "RTCPeerConnection", { value: function () {}, configurable: true });
    return { reached: true, detail: "redefined" };
  });
  await probe("connect", async () => {
    const PC = globalThis.RTCPeerConnection || globalThis.webkitRTCPeerConnection;
    const pc = new PC({ iceServers: [{ urls: "stun:127.0.0.1:47913" }, { urls: "turn:127.0.0.1:47915?transport=tcp", username: "u", credential: "p" }] });
    pc.createDataChannel("x"); await pc.setLocalDescription(await pc.createOffer());
    return { reached: true, detail: "offer set" };
  });
}} />;
