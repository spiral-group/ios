// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack activation-flood
// @threat activation
// @expect refused
// @checklist activation-flood
// @checks no-expand no-mentions

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });

  const b = make("button"); for (let i = 0; i < 500; i++) { b.click(); b.focus(); b.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true })); }
  bridge("ui.expand after the trick", await call("ui.expand", null, true));
  await call("state.shared.write", pingAll("after the trick"), true);
  note("ping after the trick", "info", "the harness reads the mentions the write carried");
}} />;
