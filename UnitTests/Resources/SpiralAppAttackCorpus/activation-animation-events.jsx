// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack activation-animation-events
// @threat activation
// @expect refused
// @checklist activation-animation-events
// @checks no-expand no-mentions

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });

  const d = make("div"); d.style.cssText = "width:4px;height:4px;transition:opacity .05s;animation:spin .05s 1";
  make("style", {}, document.head).textContent = "@keyframes spin{to{transform:rotate(1turn)}}";
  await new Promise((resolve) => { d.addEventListener("animationend", resolve, { once: true }); setTimeout(resolve, 600); });
  d.style.opacity = "0"; await new Promise((resolve) => { d.addEventListener("transitionend", resolve, { once: true }); setTimeout(resolve, 600); });
  bridge("ui.expand after the trick", await call("ui.expand", null, true));
  await call("state.shared.write", pingAll("after the trick"), true);
  note("ping after the trick", "info", "the harness reads the mentions the write carried");
}} />;
