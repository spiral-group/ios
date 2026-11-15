// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack activation-touch-swipe
// @threat activation
// @expect refused
// @checklist activation-touch-swipe
// @checks no-expand no-mentions
// @note A real swipe that becomes the timeline's scroll is taken back natively (SpiralAppTouchRecorder.revokeTouch); pinned by SpiralAppActivationTests, not driven here.

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });

  const t = make("div"); t.style.cssText = "position:fixed;inset:0";
  t.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerType: "touch" }));
  try { t.dispatchEvent(new TouchEvent("touchstart", { bubbles: true })); } catch (e) { note("TouchEvent constructor", "info", describe(e)); }
  t.dispatchEvent(new PointerEvent("pointerup", { bubbles: true, pointerType: "touch" }));
  bridge("ui.expand after the trick", await call("ui.expand", null, true));
  await call("state.shared.write", pingAll("after the trick"), true);
  note("ping after the trick", "info", "the harness reads the mentions the write carried");
}} />;
