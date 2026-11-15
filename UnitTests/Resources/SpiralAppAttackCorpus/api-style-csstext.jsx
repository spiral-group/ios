// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-style-csstext
// @threat network
// @expect blocked
// @checklist api-style-csstext

export default () => <Done after={2000} run={async () => {

  make("div").style.cssText = "width:5px;height:5px;background-image:url(" + CANARY + "/csstext)";
  document.documentElement.style.cssText += ";background:url(" + CANARY + "/csstext-root)";
}} />;
