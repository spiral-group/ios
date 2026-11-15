// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-leak-writer
// @threat isolation
// @expect by-design
// @checklist —
// @note Plants a marker everywhere it can; the next three readers must not find it.

export default () => <Done after={2000} run={async () => {

  const spots = [];
  const tryPlant = (where, fn) => { try { fn(); spots.push(where); } catch (e) {} };
  tryPlant("window.name", () => { window.name = MARKER; });
  tryPlant("history.state", () => history.replaceState({ m: MARKER }, ""));
  tryPlant("location.hash", () => { location.hash = MARKER; });
  tryPlant("localStorage", () => localStorage.setItem("m", MARKER));
  tryPlant("document.cookie", () => { document.cookie = "m=" + MARKER; });
  tryPlant("navigator property", () => { Object.defineProperty(Navigator.prototype, "spiralMarker", { value: MARKER, configurable: true }); });
  tryPlant("Object.prototype", () => { Object.prototype.spiralMarker = MARKER; });
  tryPlant("BroadcastChannel", () => { const b = new BroadcastChannel("spiral"); setInterval(() => b.postMessage(MARKER), 100); });
  tryPlant("CSS custom property on the root", () => document.documentElement.style.setProperty("--m", MARKER));
  tryPlant("parent.name", () => { parent.name = MARKER; });
  tryPlant("blob URL kept alive", () => { globalThis.__blob = URL.createObjectURL(new Blob([MARKER])); note("blob url", "info", globalThis.__blob); });
  note("planted in", "info", spots.join(", "));
  bridge("private corner write (allowed: its own corner)", await call("state.private.write", { state: { m: MARKER } }));
  bridge("shared write (allowed: its own post)", await call("state.shared.write", { op: { set: { path: ["m"], value: "MARKER-WRITER" } } }));
}} />;
