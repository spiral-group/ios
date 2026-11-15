// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-nav-window-open-self
// @threat network
// @expect blocked
// @checklist —
// @note window.open into the frame itself.

export default () => <Done after={3000} run={async () => {
  window.open(CANARY + "/open-self", "_self");
}} />;
