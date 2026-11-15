// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-nav-other-artifact
// @threat escape
// @expect blocked
// @checklist —
// @checks shell-intact scheme-paths
// @wait 5000

export default () => <Done after={2000} run={async () => {

  await finish();
  location.href = "spiral-app://a-" + "f".repeat(64) + "/index.html";
}} />;
