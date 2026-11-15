// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack request-in-flight
// @threat bridge
// @expect refused
// @checklist request-in-flight

export default () => <Done after={2000} run={async () => {

  const replies = await Promise.all(Array.from({ length: 120 }, () => call("members.basic.read", null)));
  const refused = replies.filter((r) => !r.ok && /in flight/.test(r.message || "")).length;
  note("in-flight cap", refused > 0 ? "blocked" : "REACHED", `${refused} of 120 refused for being in flight`);
}} />;
