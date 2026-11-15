// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-history-api
// @threat navigation
// @expect blocked
// @checklist —
// @checks shell-intact

export default () => <Done after={2000} run={async () => {

  await probe("pushState to the shell origin", async () => { history.pushState({}, "", "spiral-app://shell/index.html"); return { reached: true, detail: location.href }; });
  await probe("pushState to the canary", async () => { history.pushState({}, "", CANARY + "/push"); return { reached: true }; });
  await probe("replaceState same origin", async () => { history.replaceState({}, "", "/x?y#z"); return { info: true, detail: location.href }; });
  await attempt("history.go(-1)", () => history.go(-1)); await settle(300);
}} />;
