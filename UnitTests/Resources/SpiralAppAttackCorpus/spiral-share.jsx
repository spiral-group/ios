// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-share
// @threat device
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  note("navigator.share", "info", navigator.share ? "present (refused when called; see the calls below)" : "absent");
  await probe("navigator.share", async () => { await navigator.share({ text: "x", url: CANARY + "/share" }); return { reached: true }; });
  await probe("navigator.canShare", async () => ({ info: true, detail: String(navigator.canShare && navigator.canShare({ text: "x" })) }));
}} />;
