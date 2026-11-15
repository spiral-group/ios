// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack activation-timers
// @threat activation
// @expect refused
// @checklist activation-timers
// @checks no-expand no-mentions

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });

  await new Promise((resolve) => setTimeout(resolve, 0)); await new Promise(requestAnimationFrame); await Promise.resolve();
  queueMicrotask(() => {}); const mc = new MessageChannel(); await new Promise((resolve) => { mc.port1.onmessage = resolve; mc.port2.postMessage(0); });
  bridge("ui.expand after the trick", await call("ui.expand", null, true));
  await call("state.shared.write", pingAll("after the trick"), true);
  note("ping after the trick", "info", "the harness reads the mentions the write carried");
}} />;
