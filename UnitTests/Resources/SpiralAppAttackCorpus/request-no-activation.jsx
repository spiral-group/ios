// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack request-no-activation
// @threat bridge
// @expect refused
// @checklist request-no-activation
// @checks no-expand no-mentions

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });
  await new Promise((resolve) => setTimeout(async () => { await call("state.shared.write", pingAll("from a timer"), true); resolve(); }, 0));
  await Promise.resolve().then(() => call("state.shared.write", pingAll("from a promise"), true));
  await new Promise((resolve) => requestAnimationFrame(async () => { await call("state.shared.write", pingAll("from a frame"), true); resolve(); }));
  const b = make("button"); b.onclick = () => call("state.shared.write", pingAll("from a scripted click"), true); b.click();
  bridge("expand from a scripted click", await call("ui.expand", null, true)); await settle(500);
}} />;
