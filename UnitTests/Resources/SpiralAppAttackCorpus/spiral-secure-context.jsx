// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-secure-context
// @threat platform
// @expect by-design
// @checklist —
// @note Not an attack: tells which of the APIs below exist at all.

export default () => <Done after={2000} run={async () => {

  note("isSecureContext", "info", String(window.isSecureContext));
  note("origin", "info", String(self.origin) + " " + location.href);
  note("user agent", "info", navigator.userAgent);
}} />;
