// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank
// @threat network
// @expect blocked
// @checklist —
// @note target=_blank in a frame without allow-popups.

export default () => <Done after={3000} run={async () => {
  make("a", { href: CANARY + "/blank", target: "_blank" }).click();
}} />;
