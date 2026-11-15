// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack request-copy
// @threat isolation
// @expect blocked
// @checklist request-copy
// @checks no-marker
// @note Analogue: the same artifact as a different post (a forward is a new event with no relations): runs right after spiral-leak-writer.

export default () => <Done after={2000} run={async () => {

  const ctx = await call("app.context.read", null);
  note("context", "info", JSON.stringify(ctx.data));
  const shared = await call("state.shared.read", null);
  note("shared state of this copy", JSON.stringify(shared).includes("MARKER-WRITER") ? "REACHED" : "blocked", JSON.stringify(shared).slice(0, 300));
  const priv = await call("state.private.read", null);
  note("private corner of this copy", JSON.stringify(priv).includes("SPIRAL-MARKER") ? "REACHED" : "blocked", JSON.stringify(priv).slice(0, 300));
}} />;
