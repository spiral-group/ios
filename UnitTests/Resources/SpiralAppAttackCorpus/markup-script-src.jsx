// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-script-src
// @threat network
// @expect blocked
// @checklist markup-script-src

export default () => (
  <div>
    <script src={`${CANARY}/rendered-script.js`} />
    <Done after={2500} run={async () => {
  inject('<script src="' + CANARY + '/innerhtml-script.js"></scr' + 'ipt>'); make("script", { src: CANARY + "/dom-script.js" }, document.body);
}} />
  </div>
);
