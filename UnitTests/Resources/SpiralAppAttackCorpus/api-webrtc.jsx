// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-webrtc
// @threat network
// @expect blocked
// @checklist api-webrtc

export default () => <Done after={2000} run={async () => {

  for (const name of ["RTCPeerConnection", "webkitRTCPeerConnection", "RTCDataChannel", "RTCIceCandidate"]) exists(name, globalThis[name]);
  await probe("RTCPeerConnection to a STUN canary", async () => {
    const Ctor = globalThis.RTCPeerConnection || globalThis.webkitRTCPeerConnection;
    const pc = new Ctor({ iceServers: [{ urls: "stun:" + CANARY_HOST }, { urls: "turn:" + CANARY_HOST, username: "a", credential: "b" }] });
    pc.createDataChannel("x"); await pc.setLocalDescription(await pc.createOffer()); await settle(1500);
    return { reached: true, detail: pc.iceGatheringState }; });
  await probe("constructor recovered from an object's prototype chain", async () => {
    const ctor = Object.getPrototypeOf(window).constructor.prototype.RTCPeerConnection;
    return { reached: typeof ctor === "function" }; });
}} />;
