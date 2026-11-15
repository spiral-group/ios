// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-svg-animate-href
// @threat network
// @expect blocked
// @checklist markup-svg-animate-href

export default () => (
  <div>
    <svg width="20" height="20"><image id="ai" width="5" height="5"><animate attributeName="href" values={`${CANARY}/animate`} dur="0.1s" fill="freeze" /></image><a><animate attributeName="href" to="javascript:fetch(1)" dur="0.1s" /><text y="10">t</text></a></svg>
    <Done after={2500} />
  </div>
);
