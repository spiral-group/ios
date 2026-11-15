// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-form-submit
// @threat network
// @expect blocked
// @checklist api-form-submit

export default () => <Done after={2000} run={async () => {

  const f = make("form", { action: CANARY + "/form", method: "POST" }); make("input", { name: "q", value: "x" }, f);
  await attempt("form.submit()", () => f.submit());
  const g = make("form", { action: CANARY + "/form-blank", target: "_blank" }); await attempt("form target=_blank", () => g.requestSubmit());
  const h = make("form", { action: CANARY + "/form-top", target: "_top" }); await attempt("form target=_top", () => h.submit());
  const k = make("form", { action: "javascript:fetch('" + CANARY + "/form-js')" }); await attempt("form action=javascript:", () => k.submit());
}} />;
