// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-light-dark-url
// @threat network
// @expect blocked
// @checklist css-light-dark-url

export default () => (
  <div>
    <style>{`.t{background-image:light-dark(url(${CANARY}/light), url(${CANARY}/dark));color-scheme:light dark}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
