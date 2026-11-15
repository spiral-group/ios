// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-notifications
// @threat device
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  exists("Notification", globalThis.Notification);
  await probe("Notification.requestPermission", async () => ({ reached: (await Notification.requestPermission()) === "granted" }));
  await probe("new Notification", async () => ({ reached: !!new Notification("x") }));
  await probe("PushManager", async () => ({ reached: !!globalThis.PushManager }));
  await probe("Badging API", async () => { await navigator.setAppBadge(99); return { reached: true }; });
}} />;
