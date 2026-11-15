// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-style-element-dynamic
// @threat network
// @expect blocked
// @checklist api-style-element-dynamic

export default () => <Done after={2000} run={async () => {

  make("style", {}, document.head).textContent = "body{background:url(" + CANARY + "/style-el)} @import url(" + CANARY + "/style-el-import.css);";
  make("div", { class: "q" }).textContent = "x";
  make("style", {}, document.head).textContent = ".q{background:url(" + CANARY_TLS + "/style-el-tls)}";
}} />;
