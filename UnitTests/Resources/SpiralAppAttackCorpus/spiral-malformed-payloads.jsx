// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-malformed-payloads
// @threat bridge
// @expect refused
// @checklist —
// @checks report-sends

export default () => <Done after={2000} run={async () => {

  const w = (label, args) => call("state.shared.write", args).then((r) => note(label, r.ok ? "REACHED" : "blocked", JSON.stringify(r).slice(0, 160)));
  await w("op missing", {}); await w("op not an object", { op: "set" }); await w("two operations in one", { op: { set: { path: "a", value: 1 }, del: { path: "a" } } });
  await w("unknown operation", { op: { exec: { path: "a" } } }); await w("empty path", { op: { set: { path: "", value: 1 } } });
  await w("empty path component", { op: { set: { path: ["a", ""], value: 1 } } }); await w("incr NaN", { op: { incr: { path: "n", by: NaN } } });
  await w("incr Infinity", { op: { incr: { path: "n", by: Infinity } } }); await w("incr string", { op: { incr: { path: "n", by: "1" } } });
  await w("nested batch", { op: { batch: { ops: [{ batch: { ops: [{ set: { path: "a", value: 1 } }] } }] } } });
  await w("batch of 65", { op: { batch: { ops: Array.from({ length: 65 }, (_, i) => ({ set: { path: "k" + i, value: i } })) } } });
  await w("ping naming nobody", { op: { incr: { path: "n", by: 1 } }, summary: { line: "x", notify: "ping" } });
  await w("summary countdown not a date", { op: { incr: { path: "n", by: 1 } }, summary: { countdown_to: "soon" } });
  const cyclic = { op: { set: { path: "c", value: {} } } }; cyclic.op.set.value.self = cyclic; await w("cyclic args", cyclic);
  try { await w("BigInt", { op: { set: { path: "b", value: 10n } } }); } catch (e) { note("BigInt", "blocked", describe(e)); }
  let deep = 1; for (let i = 0; i < 20000; i++) deep = [deep]; await w("20 000 levels deep", { op: { set: { path: "d", value: deep } } });
  let deep2 = 1; for (let i = 0; i < 600; i++) deep2 = [deep2]; await w("600 levels deep", { op: { set: { path: "d", value: deep2 } } });
  note("__proto__ path (stored as a plain key)", "info", JSON.stringify(await call("state.shared.write", { op: { set: { path: ["__proto__", "polluted"], value: 1 } } })).slice(0, 160));
  note("1 MB request id (inside the message cap)", "info", JSON.stringify(await call("app.context.read", null, false, "i".repeat(1 << 20))).slice(0, 160));
  bridge("private write not an object", await call("state.private.write", { state: [1, 2] }));
  bridge("private write 9 KB", await call("state.private.write", { state: { x: "y".repeat(9000) } }));
  bridge("haptic with a 1 MB strength", await call("ui.haptic", { strength: "z".repeat(1 << 20) }));
}} />;
