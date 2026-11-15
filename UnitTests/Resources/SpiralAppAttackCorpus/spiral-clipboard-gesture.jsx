// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-clipboard-gesture
// @threat device
// @expect blocked
// @checklist —
// @checks no-pasteboard
// @host gesture gesture gesture gesture gesture
// @wait 20000
// @note F11 on the simulator: each write runs in a host gesture (a script the shell evaluates, which WebKit runs as a user gesture, posting into the frame). A real tap is the device pass (spiral-tap-gesture).

const text = () => {
  const t = make("textarea");
  t.value = "spiral " + ATTACK;
  t.focus();
  t.select();
  return t;
};

export default () => <Done after={1500} run={async () => {
  note("typeof navigator.clipboard", "info", typeof navigator.clipboard);
  await perGesture([
    ["clipboard.writeText", async () => { await navigator.clipboard.writeText("spiral " + ATTACK); return { reached: true, detail: "resolved" }; }],
    ["clipboard.write ClipboardItem", async () => {
      await navigator.clipboard.write([new ClipboardItem({ "text/plain": new Blob(["spiral item " + ATTACK], { type: "text/plain" }) })]);
      return { reached: true, detail: "resolved" };
    }],
    ["execCommand copy", () => { text(); return { reached: document.execCommand("copy") === true }; }],
    ["execCommand cut", () => { text(); return { reached: document.execCommand("cut") === true }; }],
    ["execCommand copy via Document.prototype", () => { text(); return { reached: Document.prototype.execCommand.call(document, "COPY") === true }; }],
  ]);
}} />;
