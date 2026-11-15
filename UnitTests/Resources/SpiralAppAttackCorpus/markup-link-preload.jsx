// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-link-preload
// @threat network
// @expect blocked
// @checklist markup-link-preload

export default () => (
  <div>
    <link rel="preload" as="image" href={`${CANARY}/preload-img`} />
    <Done after={2500} run={async () => {
  make("link", { rel: "preload", as: "fetch", href: CANARY + "/preload-fetch", crossorigin: "" }, document.head); make("link", { rel: "preload", as: "font", href: CANARY + "/preload-font", crossorigin: "" }, document.head);
}} />
  </div>
);
