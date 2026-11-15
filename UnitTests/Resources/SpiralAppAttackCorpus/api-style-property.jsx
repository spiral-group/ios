// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-style-property
// @threat network
// @expect blocked
// @checklist api-style-property

export default () => <Done after={2000} run={async () => {

  const d = make("div"); d.textContent = "x";
  d.style.setProperty("background-image", "url(" + CANARY + "/setproperty)");
  d.style.listStyleImage = "url(" + CANARY + "/liststyle)"; d.style.display = "list-item";
  d.style.borderImageSource = "url(" + CANARY + "/borderimage)"; d.style.borderWidth = "4px"; d.style.borderStyle = "solid";
}} />;
