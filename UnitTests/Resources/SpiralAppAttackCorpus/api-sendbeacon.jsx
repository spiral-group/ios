// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-sendbeacon
// @threat network
// @expect blocked
// @checklist api-sendbeacon

export default () => <Done after={2000} run={async () => {

  await probe("sendBeacon", async () => ({ reached: navigator.sendBeacon(CANARY + "/beacon", "x") === true }));
  await probe("sendBeacon restored from the prototype", async () => {
    const original = Object.getOwnPropertyDescriptor(Navigator.prototype, "sendBeacon");
    const queued = original && original.value.call(navigator, CANARY + "/beacon-proto", "x");
    return { info: true, detail: `queued: ${queued} (F8); connect-src is the control, the canary the witness` }; });
  window.addEventListener("pagehide", () => { try { Navigator.prototype.sendBeacon.call(navigator, CANARY + "/beacon-unload"); } catch (e) {} });
}} />;
