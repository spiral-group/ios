// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack activation-scroll-hover
// @threat activation
// @expect refused
// @checklist activation-scroll-hover
// @checks no-expand no-mentions

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });

  document.body.style.height = "4000px"; window.scrollTo(0, 500); document.getElementById("root").scrollTop = 200;
  document.body.dispatchEvent(new MouseEvent("mouseover", { bubbles: true })); await settle(200);
  bridge("ui.expand after the trick", await call("ui.expand", null, true));
  await call("state.shared.write", pingAll("after the trick"), true);
  note("ping after the trick", "info", "the harness reads the mentions the write carried");
}} />;
