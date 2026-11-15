// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-named-host
// @threat network
// @expect blocked
// @checklist —
// @note A host name, not an address: the connection needs a name lookup first.

export default () => <Done after={3000} run={async () => {
  make("a", { href: "http://spiral-canary-named.localhost:47913/c/spiral-link-named-host" }).click();
}} />;
