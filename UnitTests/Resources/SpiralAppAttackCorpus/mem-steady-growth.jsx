// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack mem-steady-growth
// @threat resource
// @expect contained
// @checklist mem-steady-growth
// @checks liveness

export default () => <Done after={1000} run={async () => {

  const keep = []; let mb = 0; const until = Date.now() + 6000;
  try { while (Date.now() < until && mb < 1024) { keep.push(new Array(131072).fill(mb)); mb += 1; if (mb % 32 === 0) await settle(0); } note("steady growth", "info", `${mb} MB of arrays`); }
  catch (e) { note("steady growth", "info", `${mb} MB then ${describe(e)}`); }
  globalThis.__keep = keep;
}} />;
