// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-link-prefetch
// @threat network
// @expect blocked
// @checklist markup-link-prefetch

export default () => (
  <div>
    <link rel="prefetch" href={`${CANARY}/prefetch`} />
    <Done after={2500} run={async () => {
  make("link", { rel: "prefetch", href: CANARY + "/prefetch-head" }, document.head); make("link", { rel: "prerender", href: CANARY + "/prerender" }, document.head); make("link", { rel: "next", href: CANARY + "/next" }, document.head);
}} />
  </div>
);
