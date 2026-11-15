// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-content-url
// @threat network
// @expect blocked
// @checklist css-content-url

export default () => (
  <div>
    <style>{`.t::before{content:url(${CANARY}/content)} .t::after{content:url(${CANARY_LOCALHOST}/content-lh)}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
