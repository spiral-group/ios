// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-object-embed-dynamic
// @threat network
// @expect blocked
// @checklist api-object-embed-dynamic

export default () => <Done after={2000} run={async () => {

  make("object", { data: CANARY + "/object", type: "text/html" });
  make("embed", { src: CANARY + "/embed", type: "image/svg+xml" });
  make("object", { data: "data:text/html,<img src='" + CANARY + "/object-data'>" });
}} />;
