// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack css-escaped-url
// @threat network
// @expect blocked
// @checklist css-escaped-url

export default () => (
  <div>
    <style>{`.t{background:url(\\68 ttp://127.0.0.1:47913/c/css-escaped-url/escaped)} .t::after{content:'';background:u\\72 l(${CANARY}/escaped-fn)}`}</style>
    <div className="t">x</div>
    <Done after={2500} />
  </div>
);
