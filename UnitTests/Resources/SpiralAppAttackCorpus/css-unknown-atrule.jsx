// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-unknown-atrule
// @threat network
// @expect blocked
// @checklist css-unknown-atrule

export default () => (
  <div>
    <style>{`@spiral-unknown url(${CANARY}/unknown-atrule) { .t{background:url(${CANARY}/unknown-inner)} } @-webkit-x { a{b:url(${CANARY}/wk-unknown)} } .t{background:url(${CANARY}/after-unknown)}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
