// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-svg-feimage
// @threat network
// @expect blocked
// @checklist markup-svg-feimage

export default () => (
  <div>
    <svg width="20" height="20"><filter id="fi"><feImage href={`${CANARY}/feimage`} /></filter><rect width="10" height="10" filter="url(#fi)" /></svg>
    <Done after={2500} />
  </div>
);
