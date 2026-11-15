// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack cpu-greedy-timer
// @threat resource
// @expect contained
// @checklist cpu-greedy-timer
// @checks liveness

export default () => <Done after={500} run={async () => {

  const until = Date.now() + 6000; let ticks = 0;
  await new Promise((resolve) => { const id = setInterval(() => { const s = Date.now(); while (Date.now() - s < 45) {} ticks++; if (Date.now() > until) { clearInterval(id); resolve(); } }, 0); });
  note("greedy ticks", "info", ticks);
}} />;
