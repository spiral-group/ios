// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack activation-synthetic-input
// @threat activation
// @expect refused
// @checklist activation-synthetic-input
// @checks no-expand no-mentions

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });

  const i = make("input"); i.focus(); i.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  i.dispatchEvent(new InputEvent("input", { data: "x", bubbles: true })); document.execCommand("insertText", false, "x");
  make("button").dispatchEvent(new MouseEvent("click", { bubbles: true }));
  note("navigator.userActivation.isActive", navigator.userActivation && navigator.userActivation.isActive ? "REACHED" : "blocked", String(navigator.userActivation && navigator.userActivation.isActive));
  bridge("ui.expand after the trick", await call("ui.expand", null, true));
  await call("state.shared.write", pingAll("after the trick"), true);
  note("ping after the trick", "info", "the harness reads the mentions the write carried");
}} />;
