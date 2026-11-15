// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-a-ping
// @threat network
// @expect blocked
// @checklist markup-a-ping

export default () => (
  <div>
    <a id="p" href="#here" ping={`${CANARY}/a-ping`}>x</a>
    <Done after={2500} run={async () => {
  document.getElementById("p").click();
}} />
  </div>
);
