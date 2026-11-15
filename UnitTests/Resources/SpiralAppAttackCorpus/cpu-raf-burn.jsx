// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack cpu-raf-burn
// @threat resource
// @expect contained
// @checklist cpu-raf-burn
// @checks liveness

export default () => <Done after={500} run={async () => {

  const until = Date.now() + 6000; let frames = 0;
  await new Promise((resolve) => { const step = () => { const s = performance.now(); while (performance.now() - s < 30) {} frames++; if (Date.now() < until) requestAnimationFrame(step); else resolve(); }; requestAnimationFrame(step); });
  note("burning frames", "info", frames);
}} />;
