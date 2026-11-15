// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-clipboard
// @threat device
// @expect blocked
// @checklist —
// @note Without a tap. With one: spiral-clipboard-gesture, -read-gesture and -copy-event (a host gesture), and spiral-tap-gesture (a real tap, device only; F11).

export default () => <Done after={2000} run={async () => {

  await probe("clipboard.writeText", async () => { await navigator.clipboard.writeText("spiral " + ATTACK); return { reached: true }; });
  await probe("clipboard.readText", async () => ({ reached: true, detail: (await navigator.clipboard.readText()).slice(0, 40) }));
  await probe("clipboard.write ClipboardItem", async () => { await navigator.clipboard.write([new ClipboardItem({ "text/plain": new Blob(["x"], { type: "text/plain" }) })]); return { reached: true }; });
  await probe("execCommand copy", async () => { const t = make("textarea"); t.value = "x"; t.select(); return { reached: document.execCommand("copy") }; });
  await probe("execCommand paste", async () => ({ reached: document.execCommand("paste") }));
  document.addEventListener("copy", (e) => { e.clipboardData && e.clipboardData.setData("text/plain", "hijacked"); e.preventDefault(); });
}} />;
