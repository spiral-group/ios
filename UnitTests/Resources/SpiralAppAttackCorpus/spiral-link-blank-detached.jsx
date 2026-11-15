// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-blank-detached
// @threat network
// @expect blocked
// @checklist —
// @note target=_blank on an anchor never put in the document: its click event reaches no listener on the window, so only the host's own refusal can stop it.

export default () => <Done after={3000} run={async () => {
  const a = document.createElement("a");
  a.href = CANARY + "/blank-detached";
  a.target = "_blank";
  a.click();
  const tls = document.createElement("a");
  tls.href = CANARY_TLS + "/blank-detached-tls";
  tls.target = "_blank";
  tls.click();
}} />;
