// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank-other-port
// @threat network
// @expect blocked
// @checklist —
// @note With rel=noopener noreferrer.

export default () => <Done after={3000} run={async () => {
  make("a", { href: "https://127.0.0.1:47915/c/spiral-link-blank-other-port", target: "_blank", rel: "noopener noreferrer" }).click();
}} />;
