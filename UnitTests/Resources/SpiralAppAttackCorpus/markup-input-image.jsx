// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-input-image
// @threat network
// @expect blocked
// @checklist markup-input-image

export default () => (
  <div>
    <input type="image" src={`${CANARY}/input-image`} alt="x" />
    <Done after={2500} />
  </div>
);
