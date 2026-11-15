// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-link-dns-prefetch
// @threat network
// @expect blocked
// @checklist markup-link-dns-prefetch
// @note A DNS lookup itself is not observable on loopback; the canary sees only a follow-up connection.

export default () => (
  <div>
    <link rel="dns-prefetch" href="//canary-dns-prefetch.invalid" /><link rel="dns-prefetch" href={`${CANARY}/dns`} />
    <Done after={2500} run={async () => {
  make("link", { rel: "dns-prefetch", href: "http://" + CANARY_HOST }, document.head);
}} />
  </div>
);
