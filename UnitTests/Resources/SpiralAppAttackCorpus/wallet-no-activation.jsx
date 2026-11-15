// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack wallet-no-activation
// @threat activation
// @expect refused
// @checklist wallet-no-activation
// @checks no-expand no-mentions
// @note Analogue: Spiral has no wallet. The privileged, tap-gated actions are ui.expand and a ping naming people.

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });
  bridge("expand from a timer", await new Promise((resolve) => setTimeout(async () => resolve(await call("ui.expand", null, true)), 0)));
  bridge("expand from a frame", await new Promise((resolve) => requestAnimationFrame(async () => resolve(await call("ui.expand", null, true)))));
  await call("state.shared.write", pingAll("no tap"), true);
}} />;
