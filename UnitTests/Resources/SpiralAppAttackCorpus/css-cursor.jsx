// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-cursor
// @threat network
// @expect blocked
// @checklist css-cursor

export default () => (
  <div>
    <style>{`.t{cursor:url(${CANARY}/cursor),auto} body{cursor:url(${CANARY}/cursor-body),auto}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
