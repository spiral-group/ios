// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-eval
// @threat allow-list
// @expect blocked
// @checklist api-eval
// @note eval and inline script are refused by CSP; a blob script runs by design (script-src blob:), and gains nothing CSP does not already deny.

export default () => <Done after={2000} run={async () => {

  await probe("eval", async () => ({ reached: eval("1 + 1") === 2 }));
  await probe("indirect eval", async () => ({ reached: (0, eval)("2") === 2 }));
  await probe("Function", async () => ({ reached: Function("return 3")() === 3 }));
  await probe("AsyncFunction", async () => { const F = (async () => {}).constructor; return { reached: (await F("return 4")()) === 4 }; });
  await probe("setTimeout(string)", async () => { window.__t = 0; setTimeout("window.__t = 5"); await settle(100); return { reached: window.__t === 5 }; });
  await probe("inline <script> text", async () => { window.__i = 0; const s = document.createElement("script"); s.textContent = "window.__i = 6"; document.head.appendChild(s); await settle(50); return { reached: window.__i === 6 }; });
  await probe("javascript: in an attribute handler", async () => { window.__h = 0; const d = inject('<img src="x" onerror="window.__h = 7">'); await settle(200); d.remove(); return { reached: window.__h === 7 }; });
  await probe("blob <script src>", async () => { window.__b = 0; const s = document.createElement("script"); s.src = URL.createObjectURL(new Blob(["window.__b = 8"])); document.head.appendChild(s); await settle(200); return { info: window.__b === 8, detail: window.__b === 8 ? "ran: blob: is allowed by script-src (the allow-list is not a boundary)" : "did not run" }; });
}} />;
