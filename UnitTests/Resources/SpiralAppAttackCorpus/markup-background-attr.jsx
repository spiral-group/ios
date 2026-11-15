// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-background-attr
// @threat network
// @expect blocked
// @checklist markup-background-attr

export default () => (
  <div>
    <table background={`${CANARY}/table-bg`}><tbody><tr><td background={`${CANARY}/td-bg`}>x</td></tr></tbody></table>
    <Done after={2500} run={async () => {
  document.body.setAttribute("background", CANARY + "/body-bg");
}} />
  </div>
);
