// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-base-href
// @threat network
// @expect blocked
// @checklist markup-base-href

export default () => (
  <div>
    <img id="rel" alt="" />
    <Done after={2500} run={async () => {
  make("base", { href: CANARY + "/" }, document.head); document.getElementById("rel").src = "relative-after-base"; make("img", { src: "relative-2" });
}} />
  </div>
);
