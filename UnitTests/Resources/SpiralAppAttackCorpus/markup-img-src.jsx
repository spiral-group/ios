// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-img-src
// @threat network
// @expect blocked
// @checklist markup-img-src

export default () => (
  <div>
    <img src={`${CANARY}/img`} alt="" /><img src={`${CANARY_TLS}/img-tls`} alt="" /><img src={`${CANARY_LOCALHOST}/img-lh`} alt="" /><img src="//127.0.0.1:47913/c/markup-img-src/proto-relative" alt="" />
    <Done after={2500} />
  </div>
);
