// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-leak-reader-reuse
// @threat isolation
// @expect blocked
// @checklist —
// @checks no-marker
// @note Same pooled web view as the writer, a different post, the same account.

export default () => <Done after={2000} run={async () => {

  const found = {};
  const read = (where, fn) => { try { found[where] = String(fn()); } catch (e) { found[where] = describe(e); } };
  read("window.name", () => window.name); read("history.state", () => JSON.stringify(history.state)); read("location", () => location.href);
  read("localStorage", () => localStorage.getItem("m")); read("cookie", () => document.cookie);
  read("navigator", () => navigator.spiralMarker); read("Object.prototype", () => ({}).spiralMarker);
  read("CSS root", () => getComputedStyle(document.documentElement).getPropertyValue("--m")); read("parent.name", () => parent.name);
  read("history.length", () => history.length); read("performance entries", () => performance.getEntries().map((e) => e.name).join(" ").slice(0, 300));
  await new Promise((resolve) => { try { const b = new BroadcastChannel("spiral"); b.onmessage = (e) => { found.BroadcastChannel = String(e.data); }; } catch (e) { found.BroadcastChannel = describe(e); } setTimeout(resolve, 1200); });
  const priv = await call("state.private.read", null); found.privateCorner = JSON.stringify(priv.data);
  const shared = await call("state.shared.read", null); found.sharedOfThisPost = JSON.stringify(shared.data).slice(0, 200);
  const all = JSON.stringify(found);
  note("anything of the writer's", /SPIRAL-MARKER|MARKER-WRITER/.test(all) ? "REACHED" : "blocked", all.slice(0, 700));
}} />;
