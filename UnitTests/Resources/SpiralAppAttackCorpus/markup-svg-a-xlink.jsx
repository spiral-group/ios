// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-svg-a-xlink
// @threat network
// @expect blocked
// @checklist markup-svg-a-xlink

export default () => (
  <div>
    <svg width="20" height="20"><a id="sa" href={`${CANARY}/svg-a`}><rect width="10" height="10" /></a></svg>
    <Done after={2500} run={async () => {
  document.getElementById("sa").dispatchEvent(new MouseEvent("click", { bubbles: true }));
}} />
  </div>
);
