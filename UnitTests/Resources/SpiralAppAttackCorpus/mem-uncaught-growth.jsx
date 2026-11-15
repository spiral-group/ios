// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack mem-uncaught-growth
// @threat resource
// @expect contained
// @checklist mem-uncaught-growth
// @checks liveness

export default () => <Done after={500} run={async () => {

  globalThis.__grow = []; let n = 0;
  const id = setInterval(() => { n++; globalThis.__grow.push(new Uint8Array(16 * 1024 * 1024).fill(1)); if (n > 48) clearInterval(id); throw new Error("uncaught " + n); }, 20);
  await settle(2500); note("uncaught errors while growing", "info", `${n} ticks`);
}} />;
