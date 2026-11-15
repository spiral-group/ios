// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-unknown-elements
// @threat network
// @expect blocked
// @checklist markup-unknown-elements

export default () => (
  <div>
    <spiral-x src={`${CANARY}/custom-src`} background={`${CANARY}/custom-bg`} /><image src={`${CANARY}/html-image-tag`} /><frame src={`${CANARY}/frame`} /><applet code={`${CANARY}/applet`} /><portal src={`${CANARY}/portal`} />
    <Done after={2500} />
  </div>
);
