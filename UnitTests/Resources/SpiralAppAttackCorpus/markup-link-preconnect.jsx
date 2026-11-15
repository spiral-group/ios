// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-link-preconnect
// @threat network
// @expect blocked
// @checklist markup-link-preconnect

export default () => (
  <div>
    <link rel="preconnect" href={`http://${CANARY_HOST}`} />
    <Done after={2500} run={async () => {
  make("link", { rel: "preconnect", href: "https://127.0.0.1:47915" }, document.head); make("link", { rel: "preconnect", href: "http://" + CANARY_HOST, crossorigin: "" }, document.head);
}} />
  </div>
);
