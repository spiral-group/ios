// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-picture-source
// @threat network
// @expect blocked
// @checklist markup-picture-source

export default () => (
  <div>
    <picture><source srcSet={`${CANARY}/picture-source`} media="(min-width: 1px)" /><img src="x.png" alt="" /></picture>
    <Done after={2500} />
  </div>
);
