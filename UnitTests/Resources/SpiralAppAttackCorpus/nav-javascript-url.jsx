// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack nav-javascript-url
// @threat navigation
// @expect blocked
// @checklist nav-javascript-url
// @checks shell-intact

export default () => <Done after={2000} run={async () => {

  await attempt("location = javascript:", () => { location.href = "javascript:fetch('" + CANARY + "/js-url')"; });
  const l = make("a", { href: "javascript:new Image().src='" + CANARY + "/js-anchor'" }); await attempt("a href=javascript: click", () => l.click());
  await attempt("top javascript:", () => { top.location = "javascript:alert(1)"; });
}} />;
