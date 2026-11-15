// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-self
// @threat network
// @expect blocked
// @checklist —
// @note A same-frame link to the canary, clicked by script.

export default () => <Done after={3000} run={async () => {
  make("a", { href: CANARY + "/self" }).click();
}} />;
