// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-meta-refresh
// @threat network
// @expect blocked
// @checklist markup-meta-refresh
// @checks shell-intact

export default () => (
  <div>
    <meta httpEquiv="refresh" content={`0;url=${CANARY}/meta-body`} />
    <Done after={2500} run={async () => {
  make("meta", { "http-equiv": "refresh", content: "0;url=" + CANARY + "/meta-head" }, document.head); make("meta", { "http-equiv": "Content-Security-Policy", content: "default-src *" }, document.head); await settle(800); make("img", { src: CANARY + "/after-meta-csp" });
}} />
  </div>
);
