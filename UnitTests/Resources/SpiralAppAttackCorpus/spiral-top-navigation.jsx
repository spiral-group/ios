// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-top-navigation
// @threat navigation
// @expect blocked
// @checklist —
// @checks shell-intact

export default () => <Done after={2000} run={async () => {

  await probe("top.location.href", async () => { top.location.href = "spiral-app://shell/index.html#taken"; return { reached: true }; });
  await probe("top.location.reload", async () => { top.location.reload(); return { reached: true }; });
  await probe("history.back of the top", async () => { top.history.back(); return { reached: true }; });
  const l = make("a", { href: "spiral-app://shell/index.html#a", target: "_top" }); await attempt("a target=_top", () => l.click());
}} />;
