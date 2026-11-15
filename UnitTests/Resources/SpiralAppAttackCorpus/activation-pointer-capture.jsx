// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack activation-pointer-capture
// @threat activation
// @expect refused
// @checklist activation-pointer-capture
// @checks no-expand no-mentions
// @note A press that began outside a post cannot reach its frame: the frame is a separate document behind its own web view.

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });

  const b = make("div"); b.style.cssText = "position:fixed;inset:0";
  try { b.setPointerCapture(1); } catch (e) { note("setPointerCapture with no press", "blocked", describe(e)); }
  try { await document.body.requestPointerLock(); note("requestPointerLock", "REACHED", "locked"); } catch (e) { note("requestPointerLock", "blocked", describe(e)); }
  bridge("ui.expand after the trick", await call("ui.expand", null, true));
  await call("state.shared.write", pingAll("after the trick"), true);
  note("ping after the trick", "info", "the harness reads the mentions the write carried");
}} />;
