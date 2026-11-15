// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-repeat
// @threat network
// @expect blocked
// @checklist —
// @note Twenty clicks: is every one a connection, i.e. a channel with a rate?

export default () => <Done after={3000} run={async () => {
  for (let i = 0; i < 20; i++) { make("a", { href: CANARY + "/repeat-" + i }).click(); await settle(50); }
}} />;
