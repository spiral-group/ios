// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-identity-reach
// @threat identity
// @expect by-design
// @checklist —
// @note What a post learns about its viewer and room, in full.

export default () => <Done after={2000} run={async () => {

  note("app.context.read", "info", JSON.stringify((await call("app.context.read", null)).data));
  note("members.basic.read", "info", JSON.stringify((await call("members.basic.read", null)).data).slice(0, 600));
  note("time.read", "info", JSON.stringify((await call("time.read", null)).data));
  note("handshake", "info", JSON.stringify(globalThis.__spiralInit));
}} />;
