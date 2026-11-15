// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack nav-data-html-url
// @threat navigation
// @expect blocked
// @checklist nav-data-html-url
// @checks shell-intact
// @wait 6000

export default () => <Done after={2000} run={async () => {

  await attempt("location = data:text/html", () => { location.href = "data:text/html,<img src='" + CANARY + "/data-nav'>"; }); await settle(800);
}} />;
