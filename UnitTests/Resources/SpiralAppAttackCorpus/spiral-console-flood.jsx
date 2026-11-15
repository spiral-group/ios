// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-console-flood
// @threat resource
// @expect contained
// @checklist —
// @checks liveness

export default () => <Done after={2000} run={async () => {

  for (let i = 0; i < 20000; i++) console.error("flood " + i + " " + "x".repeat(1000));
  note("console flood", "info", "20 000 lines of 1 KB");
}} />;
