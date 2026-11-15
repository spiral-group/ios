// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack wallet-grant-reuse
// @threat activation
// @expect refused
// @checklist wallet-grant-reuse
// @checks max-expand-1
// @touch yes
// @note Analogue: one touch, many expands. consumeForExpand allows one.

export default () => <Done after={2000} run={async () => {

  const replies = [];
  for (let i = 0; i < 6; i++) { replies.push((await call("ui.expand", null, true)).ok); await settle(150); }
  note("expands granted for one touch", replies.filter(Boolean).length > 1 ? "REACHED" : "blocked", JSON.stringify(replies));
}} />;
