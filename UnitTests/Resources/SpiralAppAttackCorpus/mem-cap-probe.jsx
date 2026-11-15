// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack mem-cap-probe
// @threat resource
// @expect contained
// @checklist mem-cap-probe, mem-cap-probe.js
// @checks liveness
// @note Pure JS, no DOM, so it stands for mem-cap-probe.js too. Stopped at 2 GB by the harness, not by the sandbox.

export default () => <Done after={1000} run={async () => {

  const keep = []; let mb = 0;
  try { while (mb < 2048) { keep.push(new Float64Array(131072).fill(mb)); mb++; } note("cap probe", "info", `no cap met up to ${mb} MB (harness ceiling)`); }
  catch (e) { note("cap probe", "info", `cap at ${mb} MB: ${describe(e)}`); }
  globalThis.__keep = keep;
}} />;
