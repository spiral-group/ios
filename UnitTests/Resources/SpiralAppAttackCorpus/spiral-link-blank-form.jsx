// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank-form
// @threat network
// @expect blocked
// @checklist —
// @note A form with target=_blank, for comparison.

export default () => <Done after={3000} run={async () => {
  const f = make("form", { action: CANARY + "/blank-form", target: "_blank", method: "GET" }); f.submit();
}} />;
