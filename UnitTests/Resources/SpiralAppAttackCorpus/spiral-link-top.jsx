// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-top
// @threat network
// @expect blocked
// @checklist —
// @note target=_top in a frame without allow-top-navigation.

export default () => <Done after={3000} run={async () => {
  make("a", { href: CANARY + "/top", target: "_top" }).click();
}} />;
