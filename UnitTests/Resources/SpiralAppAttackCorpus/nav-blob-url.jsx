// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack nav-blob-url
// @threat navigation
// @expect blocked
// @checklist nav-blob-url
// @checks shell-intact
// @wait 6000

export default () => <Done after={2000} run={async () => {

  const url = URL.createObjectURL(new Blob(['<img src="' + CANARY + '/blob-nav"><script>fetch("' + CANARY + '/blob-nav-fetch")<\/script>'], { type: "text/html" }));
  await attempt("location = blob:", () => { location.href = url; }); await settle(800);
}} />;
