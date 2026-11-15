// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack timer-flood
// @threat resource
// @expect contained
// @checklist timer-flood

export default () => <Done after={2000} run={async () => {

  let fired = 0; for (let i = 0; i < 100000; i++) setTimeout(() => { fired++; }, 1);
  await settle(1500); note("100 000 timers", "info", `${fired} fired`);
}} />;
