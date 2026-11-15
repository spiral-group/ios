// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-object-data
// @threat network
// @expect blocked
// @checklist markup-object-data

export default () => (
  <div>
    <object data={`${CANARY}/object`} type="image/svg+xml" /><object data={`${CANARY}/object.html`} />
    <Done after={2500} />
  </div>
);
