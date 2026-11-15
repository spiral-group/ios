// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank-repeat
// @threat network
// @expect blocked
// @checklist —
// @note Twenty target=_blank clicks: one connection each would make it a channel with a rate.

export default () => <Done after={3000} run={async () => {
  for (let i = 0; i < 20; i++) { make("a", { href: "http://127.0.0.1:47913/c/spiral-link-blank-repeat/" + i, target: "_blank" }).click(); await settle(100); }
}} />;
