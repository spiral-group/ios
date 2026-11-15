// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-css-insertrule
// @threat network
// @expect blocked
// @checklist api-css-insertrule

export default () => <Done after={2000} run={async () => {

  const s = make("style", {}, document.head).sheet; make("div", { class: "ir" }).textContent = "x";
  s.insertRule(".ir{background:url(" + CANARY + "/insertrule)}", 0);
  await attempt("insertRule @import", () => s.insertRule("@import url(" + CANARY + "/insertrule-import.css);", 0));
  await attempt("insertRule @font-face", () => { s.insertRule("@font-face{font-family:ir;src:url(" + CANARY + "/insertrule-font)}", 0); s.insertRule(".ir{font-family:ir}", 0); });
}} />;
