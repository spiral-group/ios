// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-svg-image
// @threat network
// @expect blocked
// @checklist markup-svg-image

export default () => (
  <div>
    <svg width="20" height="20"><image href={`${CANARY}/svg-image`} width="10" height="10" /><image xlinkHref={`${CANARY}/svg-xlink-image`} width="10" height="10" /></svg>
    <Done after={2500} />
  </div>
);
