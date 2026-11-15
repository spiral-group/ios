// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-link-stylesheet-dynamic
// @threat network
// @expect blocked
// @checklist api-link-stylesheet-dynamic

export default () => <Done after={2000} run={async () => {

  make("link", { rel: "stylesheet", href: CANARY + "/link.css" }, document.head);
  make("link", { rel: "stylesheet", href: CANARY_TLS + "/link.css" }, document.head);
  make("link", { rel: "alternate stylesheet", href: CANARY + "/alt.css", title: "x" }, document.head);
}} />;
