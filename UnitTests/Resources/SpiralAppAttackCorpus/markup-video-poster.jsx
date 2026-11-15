// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-video-poster
// @threat network
// @expect blocked
// @checklist markup-video-poster

export default () => (
  <div>
    <video poster={`${CANARY}/poster`} width="10" height="10" />
    <Done after={2500} />
  </div>
);
