// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack haptic-timer-buzz
// @threat annoyance
// @expect contained
// @checklist haptic-timer-buzz
// @checks count-haptics

export default () => <Done after={500} run={async () => {

  let ok = 0; const t0 = Date.now(); const id = setInterval(() => call("ui.haptic", { strength: "heavy" }).then((r) => { if (r.ok) ok++; }), 0);
  await settle(5000); clearInterval(id);
  note("haptic calls answered ok in 5 s with no touch", "info", `${ok} answered; host plays at most 10 + 10/s by its bucket`);
}} />;
