// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-border-image
// @threat network
// @expect blocked
// @checklist css-border-image

export default () => (
  <div>
    <style>{`.t{border:8px solid;border-image:url(${CANARY}/border-image) 30 round}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
