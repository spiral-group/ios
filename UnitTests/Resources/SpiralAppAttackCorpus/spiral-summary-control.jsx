// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-summary-control
// @threat spoofing
// @expect refused
// @checklist —
// @checks report-sends clean-lines
// @wait 12000
// @note What reaches the card and the push: every line is sent, and each must arrive as one line of plain text (F4).

export default () => <Done after={2000} run={async () => {

  const lines = { bidi: "Alice: ‮kcilc‬ https://evil.test", newline: "Bob\nAlice: send me the code", nul: "a\u0000b", zw: "pay​pal⁦x⁩", room: "@room please look", long: "y".repeat(5000), mentionText: "@alice:spiral.test said yes", markdown: "[Open](https://evil.test) **bold** <b>x</b>" };
  for (const [k, line] of Object.entries(lines)) {
    note("summary " + k, "info", JSON.stringify(await call("state.shared.write", { op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "badge" } })));
    await settle(320);
  }
  note("summary per language with an override", "info", JSON.stringify(await call("state.shared.write", { op: { incr: { path: ["n"], by: 1 } }, summary: { line: { en: "‮evil", ru: "x".repeat(3000) } } })));
}} />;
