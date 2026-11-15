// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-link-stylesheet
// @threat network
// @expect blocked
// @checklist markup-link-stylesheet

export default () => (
  <div>
    <link rel="stylesheet" href={`${CANARY}/link-rendered.css`} /><link rel="icon" href={`${CANARY}/icon`} /><link rel="apple-touch-icon" href={`${CANARY}/touch-icon`} /><link rel="manifest" href={`${CANARY}/manifest`} />
    <Done after={2500} />
  </div>
);
