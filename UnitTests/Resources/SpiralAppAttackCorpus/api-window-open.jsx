// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-window-open
// @threat navigation
// @expect blocked
// @checklist api-window-open
// @checks shell-intact

export default () => <Done after={2000} run={async () => {

  await probe("window.open(canary)", async () => { const w = window.open(CANARY + "/open"); return { reached: !!w, detail: String(w) }; });
  await probe("window.open about:blank then write", async () => { const w = window.open(""); if (w) w.document.write('<img src="' + CANARY + '/open-write">'); return { reached: !!w }; });
  await probe("window.open tel:", async () => ({ reached: !!window.open("tel:+10000000000") }));
  await probe("window.open with noopener", async () => { window.open(CANARY + "/open-noopener", "_blank", "noopener"); return { info: true }; });
}} />;
