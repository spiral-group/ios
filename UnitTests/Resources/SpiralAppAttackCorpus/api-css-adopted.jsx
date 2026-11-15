// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-css-adopted
// @threat network
// @expect blocked
// @checklist api-css-adopted

export default () => <Done after={2000} run={async () => {

  await attempt("adoptedStyleSheets", () => { const s = new CSSStyleSheet(); s.replaceSync("body{background:url(" + CANARY + "/adopted)}"); document.adoptedStyleSheets = [s]; });
  await attempt("replace() with @import", () => new CSSStyleSheet().replace("@import url(" + CANARY + "/adopted-import.css);"));
}} />;
