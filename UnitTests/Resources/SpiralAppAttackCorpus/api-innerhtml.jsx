// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-innerhtml
// @threat network
// @expect blocked
// @checklist api-innerhtml

export default () => <Done after={2000} run={async () => {

  inject('<img src="' + CANARY + '/innerhtml-img"><div style="background:url(' + CANARY + '/innerhtml-bg)">x</div><link rel="stylesheet" href="' + CANARY + '/innerhtml-css">');
  document.body.insertAdjacentHTML("beforeend", "");
}} />;
