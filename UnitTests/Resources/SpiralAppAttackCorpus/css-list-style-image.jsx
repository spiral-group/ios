// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-list-style-image
// @threat network
// @expect blocked
// @checklist css-list-style-image

export default () => (
  <div>
    <style>{`.t{display:list-item;list-style-image:url(${CANARY}/list)} ul li{list-style:url(${CANARY}/list2)}`}</style>
    <div className="t">x</div><ul><li>y</li></ul>
    <Done after={2500} />
  </div>
);
