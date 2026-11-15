// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-clipboard-read-gesture
// @threat device
// @expect blocked
// @checklist —
// @host gesture gesture gesture
// @wait 24000
// @note Reading the pasteboard in a host gesture. iOS asks with its Paste callout, which only a person can tap, so a read that waits is not a read; whether a tapped callout hands the text over is the device pass.

const settled = (promise, ms) => Promise.race([promise, settle(ms).then(() => { throw new Error(`no answer in ${ms} ms (the Paste callout waits for a person)`); })]);

export default () => <Done after={1500} run={async () => {
  await perGesture([
    ["clipboard.readText", async () => ({ reached: true, detail: String(await settled(navigator.clipboard.readText(), 3000)).slice(0, 40) })],
    ["clipboard.read", async () => ({ reached: true, detail: `${(await settled(navigator.clipboard.read(), 3000)).length} items` })],
    ["execCommand paste", () => {
      const t = make("textarea");
      t.focus();
      return { reached: document.execCommand("paste") === true || t.value !== "", detail: `pasted ${t.value.length} chars` };
    }],
    ...["PasteAsPlainText", "PasteAndMatchStyle", "PasteAsQuotation"].map((command) => [`execCommand ${command}`, () => {
      const t = make("textarea");
      t.focus();
      return { reached: document.execCommand(command) === true || t.value !== "", detail: `pasted ${t.value.length} chars` };
    }]),
  ]);
}} />;
