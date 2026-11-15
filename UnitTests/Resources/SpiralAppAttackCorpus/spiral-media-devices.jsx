// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-media-devices
// @threat device
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  note("navigator.mediaDevices", "info", navigator.mediaDevices ? "present (refused when called; see the calls below)" : "absent");
  await probe("getUserMedia audio+video", async () => { const s = await navigator.mediaDevices.getUserMedia({ audio: true, video: true }); return { reached: !!s }; });
  await probe("enumerateDevices", async () => { const d = await navigator.mediaDevices.enumerateDevices(); return { reached: d.some((x) => x.label), detail: JSON.stringify(d).slice(0, 200) }; });
  await probe("getDisplayMedia", async () => ({ reached: !!(await navigator.mediaDevices.getDisplayMedia()) }));
  await probe("webkitGetUserMedia", async () => ({ reached: typeof navigator.webkitGetUserMedia === "function" }));
  await probe("input capture=camera click", async () => { const i = make("input", { type: "file", accept: "image/*", capture: "environment" }); i.click(); return { info: true, detail: "clicked without a tap" }; });
}} />;
