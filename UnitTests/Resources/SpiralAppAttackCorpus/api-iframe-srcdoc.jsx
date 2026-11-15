// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-iframe-srcdoc
// @threat escape
// @expect blocked
// @checklist api-iframe-srcdoc

export default () => <Done after={2000} run={async () => {

  make("iframe", { srcdoc: '<img src="' + CANARY + '/srcdoc-img"><script>fetch("' + CANARY + '/srcdoc-fetch")<\/script>' });
  make("iframe", { src: "data:text/html,<img src='" + CANARY + "/data-frame'>" });
  make("iframe", { src: CANARY + "/frame-src" });
  await settle(800);
}} />;
