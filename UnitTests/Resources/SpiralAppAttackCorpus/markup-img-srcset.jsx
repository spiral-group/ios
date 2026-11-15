// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-img-srcset
// @threat network
// @expect blocked
// @checklist markup-img-srcset

export default () => (
  <div>
    <img srcSet={`${CANARY}/srcset-1 1x, ${CANARY}/srcset-2 2x, ${CANARY}/srcset-3 3x`} alt="" /><img sizes="10px" srcSet={`${CANARY}/srcset-w 100w`} alt="" />
    <Done after={2500} />
  </div>
);
