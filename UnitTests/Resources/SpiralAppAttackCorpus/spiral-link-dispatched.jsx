// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-dispatched
// @threat network
// @expect blocked
// @checklist —
// @note A synthetic click event on a same-frame link.

export default () => <Done after={3000} run={async () => {
  make("a", { href: CANARY + "/dispatched" }).dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }));
}} />;
