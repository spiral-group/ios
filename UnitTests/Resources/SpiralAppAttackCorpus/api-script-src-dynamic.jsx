// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-script-src-dynamic
// @threat network
// @expect blocked
// @checklist api-script-src-dynamic

export default () => <Done after={2000} run={async () => {

  make("script", { src: CANARY + "/script.js" }, document.head);
  make("script", { src: CANARY_TLS + "/script.js" }, document.head);
  make("script", { src: CANARY + "/module.js", type: "module" }, document.head);
  make("script", { src: "spiral-app://shell/shell.js", type: "module" }, document.head);
}} />;
