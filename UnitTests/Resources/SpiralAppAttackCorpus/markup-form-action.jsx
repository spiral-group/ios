// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack markup-form-action
// @threat network
// @expect blocked
// @checklist markup-form-action

export default () => (
  <div>
    <form id="f" action={`${CANARY}/form-action`} method="post"><input name="a" defaultValue="b" /><button id="b">go</button><button formAction={`${CANARY}/formaction`} id="c">c</button></form>
    <Done after={2500} run={async () => {
  document.getElementById("b").click(); await settle(200); document.getElementById("c").click();
}} />
  </div>
);
