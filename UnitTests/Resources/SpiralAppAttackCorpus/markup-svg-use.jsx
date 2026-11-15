// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-svg-use
// @threat network
// @expect blocked
// @checklist markup-svg-use

export default () => (
  <div>
    <svg width="20" height="20"><use href={`${CANARY}/use.svg#a`} /><use xlinkHref={`${CANARY}/use-xlink.svg#b`} /></svg>
    <Done after={2500} />
  </div>
);
