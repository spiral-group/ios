// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-img-onerror
// @threat network
// @expect blocked
// @checklist markup-img-onerror

export default () => (
  <div>
    <img src="missing.png" alt="" onError={(e) => { e.currentTarget.onerror = null; e.currentTarget.src = CANARY + "/onerror"; }} />
    <Done after={2500} />
  </div>
);
