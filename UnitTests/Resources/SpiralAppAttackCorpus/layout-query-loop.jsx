// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack layout-query-loop
// @threat resource
// @expect contained
// @checklist layout-query-loop
// @checks liveness

export default () => <Done after={500} run={async () => {

  const d = make("div"); const until = Date.now() + 5000; let n = 0;
  while (Date.now() < until) { d.style.width = (n % 300) + "px"; n += d.offsetWidth > -1 ? 1 : 0; }
  note("forced layouts in 5 s", "info", n);
}} />;
