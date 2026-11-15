// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-anchor-autoclick
// @threat navigation
// @expect blocked
// @checklist api-anchor-autoclick
// @checks shell-intact

export default () => <Done after={2000} run={async () => {

  for (const [target, path] of [["_self", "a-self"], ["_blank", "a-blank"], ["_top", "a-top"], ["_parent", "a-parent"]]) {
    const el = make("a", { href: CANARY + "/" + path, target }); await attempt("a.click target=" + target, () => el.click()); await settle(200);
  }
  const d = make("a", { href: CANARY + "/a-download", download: "x.txt" }); await attempt("a download", () => d.click());
  const e = make("a", { href: CANARY + "/a-event" }); await attempt("dispatched MouseEvent", () => e.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true })));
}} />;
