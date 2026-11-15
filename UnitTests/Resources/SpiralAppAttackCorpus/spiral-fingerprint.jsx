// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-fingerprint
// @threat identity
// @expect by-design
// @checklist —
// @checks report-sends
// @note The one exit a post has is the room (decision 235: a write needs no tap). Who opened the post, and a device print, reach every member.

export default () => <Done after={2000} run={async () => {

  const c = document.createElement("canvas"); const g = c.getContext("2d"); g.font = "14px serif"; g.fillText("Spiral 🌀", 2, 14);
  let gl = "none"; try { const x = document.createElement("canvas").getContext("webgl"); const d = x.getExtension("WEBGL_debug_renderer_info"); gl = d ? x.getParameter(d.UNMASKED_RENDERER_WEBGL) : x.getParameter(x.RENDERER); } catch (e) { gl = describe(e); }
  const print = { ua: navigator.userAgent, lang: navigator.languages, tz: Intl.DateTimeFormat().resolvedOptions().timeZone, screen: [screen.width, screen.height, devicePixelRatio], cores: navigator.hardwareConcurrency, mem: navigator.deviceMemory, touch: navigator.maxTouchPoints, gl, canvas: c.toDataURL().length, dark: matchMedia("(prefers-color-scheme: dark)").matches, reducedMotion: matchMedia("(prefers-reduced-motion: reduce)").matches, textSize: getComputedStyle(document.documentElement).fontSize };
  note("what a post can read about the phone", "info", JSON.stringify(print));
  bridge("written to the room with nobody touching", await call("state.shared.write", { op: { set: { path: ["seen", ATTACK], value: JSON.stringify(print).slice(0, 900) } } }));
}} />;
