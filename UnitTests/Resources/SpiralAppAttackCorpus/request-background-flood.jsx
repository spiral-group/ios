// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack request-background-flood
// @threat bridge
// @expect refused
// @checklist request-background-flood
// @checks max-sends-25
// @note Untouched writes are allowed (decision 235); the token bucket holds them to 10 at once plus one per 300 ms.

export default () => <Done after={500} run={async () => {

  let sent = 0, ok = 0; const go = async () => { sent++; const r = await call("state.shared.write", { op: { incr: { path: ["n"], by: 1 } } }); if (r.ok) ok++; };
  const until = Date.now() + 4000; const loops = [];
  while (Date.now() < until) { loops.push(go()); await settle(5); }
  await Promise.all(loops);
  note("writes accepted with nobody touching", "info", `${ok} of ${sent} accepted in 4 s`);
}} />;
