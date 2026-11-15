// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-nav-location-self
// @threat network
// @expect blocked
// @checklist —
// @note location.href, for comparison with a link click.

export default () => <Done after={3000} run={async () => {
  location.href = CANARY + "/location";
}} />;
