// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-svg-set
// @threat network
// @expect blocked
// @checklist markup-svg-set

export default () => (
  <div>
    <svg width="20" height="20"><image width="5" height="5"><set attributeName="href" to={`${CANARY}/svg-set`} begin="0s" /></image></svg>
    <Done after={2500} />
  </div>
);
