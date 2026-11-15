// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-video-source
// @threat network
// @expect blocked
// @checklist markup-video-source

export default () => (
  <div>
    <video width="10" height="10" preload="auto"><source src={`${CANARY}/video-source.mp4`} type="video/mp4" /><track src={`${CANARY}/track.vtt`} default /></video><video src={`${CANARY}/video-src`} preload="auto" />
    <Done after={2500} />
  </div>
);
