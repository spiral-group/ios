// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-iframe-src
// @threat network
// @expect blocked
// @checklist markup-iframe-src

export default () => (
  <div>
    <iframe src={`${CANARY}/iframe`} /><iframe src="spiral-app://shell/index.html" /><iframe srcDoc={`<img src="${CANARY}/iframe-srcdoc">`} />
    <Done after={2500} />
  </div>
);
