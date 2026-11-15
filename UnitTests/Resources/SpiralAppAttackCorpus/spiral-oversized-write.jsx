// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-oversized-write
// @threat bridge
// @expect refused
// @checklist —
// @checks report-sends max-content-32768

export default () => <Done after={2000} run={async () => {

  bridge("70 KB request", await call("state.shared.write", { op: { set: { path: "big", value: "x".repeat(70000) } } }));
  bridge("40 KB action (over the 32 KB content cap)", await call("state.shared.write", { op: { set: { path: "big", value: "x".repeat(40000) } } }));
  bridge("17 KB state (over the 16 KB budget)", await call("state.shared.write", { op: { set: { path: "big", value: "x".repeat(17000) } } }));
  let ok = 0; for (let i = 0; i < 10; i++) { const r = await call("state.shared.write", { op: { set: { path: ["grow", "k" + i], value: "y".repeat(1900) } } }); if (r.ok) ok++; }
  note("growing in 1.9 KB steps", "info", `${ok} of 10 accepted before the budget`);
}} />;
