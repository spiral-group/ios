// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank-own-origin
// @threat navigation
// @expect blocked
// @checklist —
// @checks shell-intact
// @note target=_blank to the post's own origin and to the shell: a new window is refused whatever it points at.

export default () => <Done after={3000} run={async () => {
  make("a", { href: location.href, target: "_blank" }).click();
  make("a", { href: "spiral-app://shell/index.html", target: "_blank" }).click();
  make("a", { href: CANARY + "/after-own-origin", target: "_blank" }).click();
}} />;
