// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-parent
// @threat network
// @expect blocked
// @checklist —
// @note target=_parent.

export default () => <Done after={3000} run={async () => {
  make("a", { href: CANARY + "/parent", target: "_parent" }).click();
}} />;
