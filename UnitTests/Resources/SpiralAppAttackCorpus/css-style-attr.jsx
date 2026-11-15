// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-style-attr
// @threat network
// @expect blocked
// @checklist css-style-attr

export default () => (
  <div>
    <div dangerouslySetInnerHTML={{ __html: '<span style="background:url(' + CANARY + '/style-attr)">x</span>' }} />
    <div style={{ backgroundImage: `url(${CANARY}/react-style)` }}>y</div>
    <Done after={2500} />
  </div>
);
