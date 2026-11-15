// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-import
// @threat network
// @expect blocked
// @checklist css-import

export default () => (
  <div>
    <style>{`@import url(${CANARY}/import.css); @import '${CANARY_TLS}/import2.css';`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
