// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-deep-recursion
// @threat resource
// @expect contained
// @checklist —
// @checks liveness

export default () => <Done after={2000} run={async () => {

  const f = (n) => f(n + 1) + 1; await probe("unbounded recursion", async () => { f(0); return { reached: true }; });
  const g = (n) => n === 0 ? 0 : 1 + g(n - 1); await probe("100k frames", async () => ({ info: true, detail: g(100000) }));
}} />;
