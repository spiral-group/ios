// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-background-url
// @threat network
// @expect blocked
// @checklist css-background-url

export default () => (
  <div>
    <style>{`.t{background:url(${CANARY}/bg)} .t::after{content:'';background-image:url(${CANARY_TLS}/bg-tls)}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
