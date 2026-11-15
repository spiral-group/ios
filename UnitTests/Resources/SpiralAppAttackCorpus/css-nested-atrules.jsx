// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-nested-atrules
// @threat network
// @expect blocked
// @checklist css-nested-atrules

export default () => (
  <div>
    <style>{`@media all{@supports (display:block){@layer x{@container (min-width:0px){.t{background:url(${CANARY}/nested)}}}}} .t{container-type:inline-size} @scope (div){.t{border-image:url(${CANARY}/scope) 1}}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
