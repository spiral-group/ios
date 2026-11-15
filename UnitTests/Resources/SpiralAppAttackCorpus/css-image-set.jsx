// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-image-set
// @threat network
// @expect blocked
// @checklist css-image-set

export default () => (
  <div>
    <style>{`.t{background-image:image-set(url(${CANARY}/set-1x) 1x, '${CANARY}/set-2x' 2x)} .t::after{content:'';background:-webkit-image-set(url(${CANARY}/wk-set) 1x)}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
