// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-nav-shell
// @threat escape
// @expect blocked
// @checklist —
// @checks shell-intact scheme-paths
// @wait 5000
// @note Prior audit L2: the navigation policy checks the scheme only, so a frame may load the shell document.

export default () => <Done after={2000} run={async () => {

  note("about to load the shell into this frame", "info", "");
  await finish();
  location.href = "spiral-app://shell/index.html";
}} />;
