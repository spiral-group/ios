// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-geolocation
// @threat device
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  note("navigator.geolocation", "info", navigator.geolocation ? "present (refused when called; see the calls below)" : "absent");
  await probe("getCurrentPosition", () => new Promise((resolve, reject) => { navigator.geolocation.getCurrentPosition((p) => resolve({ reached: true, detail: p.coords.latitude }), (e) => reject(new Error("code " + e.code + " " + e.message)), { timeout: 1500 }); setTimeout(() => reject(new Error("no answer")), 2000); }));
  await probe("permissions.query geolocation", async () => ({ info: true, detail: (await navigator.permissions.query({ name: "geolocation" })).state }));
}} />;
