// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-var-url
// @threat network
// @expect blocked
// @checklist css-var-url

export default () => (
  <div>
    <style>{`:root{--u:url(${CANARY}/var)} .t{background-image:var(--u)} .t::after{content:'';--v:'${CANARY}/var-str';background-image:url(var(--v))}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
