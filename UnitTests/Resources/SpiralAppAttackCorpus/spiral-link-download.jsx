// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-download
// @threat network
// @expect blocked
// @checklist —
// @note download in a frame without allow-downloads.

export default () => <Done after={3000} run={async () => {
  make("a", { href: CANARY + "/download", download: "x.txt" }).click();
}} />;
