// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-vibrate-sensors
// @threat device
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  await probe("navigator.vibrate", async () => ({ reached: navigator.vibrate ? navigator.vibrate([200, 100, 200]) : false }));
  await probe("DeviceMotionEvent.requestPermission", async () => ({ reached: (await DeviceMotionEvent.requestPermission()) === "granted" }));
  await probe("deviceorientation events", () => new Promise((resolve) => { let got = false; window.addEventListener("deviceorientation", (e) => { got = e.alpha !== null; }); setTimeout(() => resolve({ reached: got }), 800); }));
  await probe("Battery", async () => ({ reached: !!(await navigator.getBattery()) }));
  await probe("Wake Lock", async () => ({ reached: !!(await navigator.wakeLock.request("screen")) }));
  await probe("Fullscreen", async () => { await document.documentElement.requestFullscreen(); return { reached: true }; });
  await probe("webkitEnterFullscreen on video", async () => { const v = make("video"); v.webkitEnterFullscreen(); return { reached: true }; });
}} />;
