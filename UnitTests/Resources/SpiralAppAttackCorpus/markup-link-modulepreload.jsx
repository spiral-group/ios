// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-link-modulepreload
// @threat network
// @expect blocked
// @checklist markup-link-modulepreload

export default () => (
  <div>
    <link rel="modulepreload" href={`${CANARY}/modulepreload.js`} />
    <Done after={2500} run={async () => {
  make("link", { rel: "modulepreload", href: CANARY + "/modulepreload-head.js" }, document.head);
}} />
  </div>
);
