// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-area
// @threat network
// @expect blocked
// @checklist —
// @note An image-map area.

export default () => <Done after={3000} run={async () => {
  const m = make("map", { name: "m" }); const ar = make("area", { href: CANARY + "/area", shape: "default" }, m); ar.click();
}} />;
