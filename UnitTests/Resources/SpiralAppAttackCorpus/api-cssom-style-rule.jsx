// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-cssom-style-rule
// @threat network
// @expect blocked
// @checklist api-cssom-style-rule

export default () => <Done after={2000} run={async () => {

  const s = make("style", {}, document.head); s.textContent = ".cr{color:red}"; make("div", { class: "cr" }).textContent = "x";
  s.sheet.cssRules[0].style.backgroundImage = "url(" + CANARY + "/cssom-rule)";
  s.sheet.cssRules[0].style.setProperty("mask-image", "url(" + CANARY + "/cssom-mask)");
}} />;
