// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-svg-dynamic
// @threat network
// @expect blocked
// @checklist api-svg-dynamic

export default () => <Done after={2000} run={async () => {

  const svg = make("svg", { width: "20", height: "20" }, document.body, SVG);
  make("image", { href: CANARY + "/svg-dyn-image", width: "10", height: "10" }, svg, SVG);
  const u = document.createElementNS(SVG, "use"); u.setAttributeNS(XLINK, "xlink:href", CANARY + "/svg-dyn-use#a"); svg.appendChild(u);
  make("feImage", { href: CANARY + "/svg-dyn-feimage" }, make("filter", { id: "f" }, svg, SVG), SVG);
}} />;
