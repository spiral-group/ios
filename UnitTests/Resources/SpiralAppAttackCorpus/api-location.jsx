// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-location
// @threat navigation
// @expect blocked
// @checklist api-location
// @checks shell-intact

export default () => <Done after={2000} run={async () => {

  await attempt("location.assign", () => location.assign(CANARY + "/assign"));
  await settle(300);
  await attempt("location.replace", () => location.replace(CANARY + "/replace"));
  await settle(300);
  await attempt("location.href", () => { location.href = CANARY + "/href"; });
  await settle(300);
  await probe("top.location", async () => { top.location = CANARY + "/top"; return { reached: true }; });
  await probe("parent.location.href", async () => { parent.location.href = CANARY + "/parent"; return { reached: true }; });
}} />;
