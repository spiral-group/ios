// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-embed-src
// @threat network
// @expect blocked
// @checklist markup-embed-src

export default () => (
  <div>
    <embed src={`${CANARY}/embed`} type="text/html" /><embed src={`${CANARY}/embed.svg`} type="image/svg+xml" />
    <Done after={2500} />
  </div>
);
