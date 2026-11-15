// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-rtl-names
// @threat spoofing
// @expect by-design
// @checklist —
// @checks report-sends
// @note A member named with a bidi override, read by a post and put in its line.

export default () => <Done after={2000} run={async () => {

  const people = (await call("members.basic.read", null)).data;
  note("names as the bridge gives them", "info", JSON.stringify(people).replace(/[‪-‮⁦-⁩]/g, (c) => "<U+" + c.charCodeAt(0).toString(16).toUpperCase() + ">"));
  const name = (people.members || []).map((m) => m.displayName || "").find((n) => /[‪-‮]/.test(n)) || "";
  bridge("a name with an override in the summary", await call("state.shared.write", { op: { incr: { path: ["n"], by: 1 } }, summary: { line: name + " won", notify: "badge" } }));
}} />;
