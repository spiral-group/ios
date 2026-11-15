// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-mutation-after-load
// @threat network
// @expect blocked
// @checklist api-mutation-after-load

export default () => (
  <div>
    <img id="late" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" alt="" />
    <a id="link" href="#x">x</a>
    <Done after={3000} run={async () => {

  await settle(1000);
  document.getElementById("late").src = CANARY + "/late-img";
  document.getElementById("link").setAttribute("ping", CANARY + "/late-ping");
  document.getElementById("link").click();
  document.body.style.backgroundImage = "url(" + CANARY + "/late-bg)";
}} />
  </div>
);
