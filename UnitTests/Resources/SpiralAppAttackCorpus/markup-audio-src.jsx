// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-audio-src
// @threat network
// @expect blocked
// @checklist markup-audio-src

export default () => (
  <div>
    <audio src={`${CANARY}/audio`} preload="auto" autoPlay /><audio><source src={`${CANARY}/audio-source`} /></audio>
    <Done after={2500} />
  </div>
);
