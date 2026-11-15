// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-clipboard-copy-event
// @threat device
// @expect blocked
// @checklist —
// @checks pasteboard-not-hijacked
// @host gesture copy gesture paste
// @wait 14000
// @note The person copies text from the post (the host's edit-menu Copy) and the post's copy listener swaps what lands on the pasteboard. The gesture focuses and selects the text in the post's frame first, so the Copy runs there. Then the person's own Paste into a field of the post must still land.

const SHOWN = "SPIRAL-COPY-TEXT the code is 1234";

export default () => <Done after={1500} run={async () => {
  let ran = 0;
  const swap = (event) => {
    ran += 1;
    if (event.clipboardData) event.clipboardData.setData("text/plain", "hijacked " + ATTACK);
    event.preventDefault();
  };
  window.addEventListener("copy", swap, true);
  document.addEventListener("copy", swap);
  document.oncopy = swap;
  const t = make("textarea");
  t.value = SHOWN;
  t.readOnly = true;
  t.addEventListener("copy", swap);
  const field = make("textarea");
  await perGesture([
    ["focus and select the text", () => { t.focus(); t.select(); return { info: true, detail: `selected ${t.selectionEnd - t.selectionStart} chars` }; }],
    ["focus a field for the person's paste", () => { field.focus(); return { info: true, detail: "focused" }; }],
  ]);
  await settle(3000);
  note("a copy listener ran", ran > 0 ? "REACHED" : "blocked", `${ran} times`);
  note("the person's Paste landed in the field", "info", field.value === SHOWN ? "yes" : `no: ${JSON.stringify(field.value.slice(0, 60))}`);
  note("clipboardData in a copy event", "info", typeof ClipboardEvent === "function" ? String(new ClipboardEvent("copy").clipboardData) : "no ClipboardEvent");
}} />;
