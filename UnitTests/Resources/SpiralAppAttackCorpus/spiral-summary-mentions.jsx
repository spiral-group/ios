// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-summary-mentions
// @threat spoofing
// @expect refused
// @checklist —
// @checks report-sends mentions-members-only
// @touch yes
// @note After one real tap a post may ping whom it names (decision 235). Who may it name?

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });
  await call("state.shared.write", pingAll("touched ping to everyone"), true);
  await settle(350);
  await call("state.shared.write", { op: { incr: { path: ["n"], by: 1 } }, summary: { line: "x", notify: "ping", notify_users: ["@viewer:spiral.test", "@assistant-x:spiral.test", "@nobody:elsewhere.test", "@bob:spiral.test", "@bob:spiral.test"] } }, true);
}} />;
