// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-mask
// @threat network
// @expect blocked
// @checklist css-mask

export default () => (
  <div>
    <style>{`.t{-webkit-mask-image:url(${CANARY}/mask);mask:url(${CANARY}/mask2);-webkit-mask-box-image:url(${CANARY}/mask-box)}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
