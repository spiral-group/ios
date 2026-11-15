// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-owned-forge
// @threat state rules
// @expect refused
// @checklist —
// @checks owned-intact
// @note by.<userId> is writable only by <userId> (§ 5.34): the fold must show nothing under another member's name that they did not write.

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const other = ((people.data && people.data.members) || []).map((m) => m.userId).find((id) => !id.includes("viewer"));
  note("forging for", "info", other);
  bridge("set by.<other> (array path)", await call("state.shared.write", { op: { set: { path: ["by", other, "vote"], value: "forged" } } }));
  bridge("set by.<other> (dotted path)", await call("state.shared.write", { op: { set: { path: "by." + other + ".vote", value: "forged" } } }));
  bridge("batch hiding by.<other>", await call("state.shared.write", { op: { batch: { ops: [{ incr: { path: ["n"], by: 1 } }, { set: { path: ["by", other, "seat"], value: 1 } }] } } }));
  bridge("delete the whole by namespace", await call("state.shared.write", { op: { del: { path: ["by"] } } }));
  bridge("listAppend into by", await call("state.shared.write", { op: { listAppend: { path: ["by"], item: { [other]: 1 } } } }));
  bridge("set the whole by namespace", await call("state.shared.write", { op: { set: { path: ["by"], value: { [other]: { vote: "forged-root" }, "@viewer:spiral.test": { vote: "mine" } } } } }));
  bridge("setIfAbsent under by (a no-op now)", await call("state.shared.write", { op: { setIfAbsent: { path: ["by"], value: { [other]: { seat: 7 } } } } }));
}} />;
