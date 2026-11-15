// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-font-face
// @threat network
// @expect blocked
// @checklist css-font-face

export default () => (
  <div>
    <style>{`@font-face{font-family:canary;src:url(${CANARY}/font.woff2) format('woff2'),url(${CANARY_TLS}/font.ttf)} .t{font-family:canary}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
