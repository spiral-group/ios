// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-foreignobject
// @threat network
// @expect blocked
// @checklist markup-foreignobject

export default () => (
  <div>
    <svg width="40" height="40"><foreignObject width="40" height="40"><img src={`${CANARY}/foreign-img`} /><div style={{ background: `url(${CANARY}/foreign-bg)` }}>x</div></foreignObject></svg>
    <Done after={2500} />
  </div>
);
