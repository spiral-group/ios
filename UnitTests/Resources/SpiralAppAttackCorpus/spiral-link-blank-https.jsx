// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank-https
// @threat network
// @expect blocked
// @checklist —
// @note target=_blank over https.

export default () => <Done after={3000} run={async () => {
  make("a", { href: CANARY_TLS + "/blank-https", target: "_blank" }).click();
}} />;
