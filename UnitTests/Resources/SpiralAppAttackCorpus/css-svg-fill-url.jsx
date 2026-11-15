// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-svg-fill-url
// @threat network
// @expect blocked
// @checklist css-svg-fill-url

export default () => (
  <div>
    <style>{`.t{fill:url(${CANARY}/fill#g);stroke:url(${CANARY}/stroke#g);filter:url(${CANARY}/filter#f);clip-path:url(${CANARY}/clip#c)}`}</style>
    <svg className="t" width="20" height="20"><rect width="10" height="10" /></svg>
    <Done after={2500} />
  </div>
);
