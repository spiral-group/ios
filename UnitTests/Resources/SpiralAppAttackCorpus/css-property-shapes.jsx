// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-property-shapes
// @threat network
// @expect blocked
// @checklist —
// @note Ours: three more properties that take a URL.

export default () => (
  <div>
    <style>{`.t{shape-outside:url(${CANARY}/shape);float:left;width:9px;height:9px} .u{offset-path:url(${CANARY}/offset#p)} .v{background:paint(x),url(${CANARY}/after-paint)}`}</style>
    <div className="t" /><div className="u">u</div><div className="v">v</div>
    <Done after={2500} />
  </div>
);
