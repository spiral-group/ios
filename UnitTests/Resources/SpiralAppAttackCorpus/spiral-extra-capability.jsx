// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-extra-capability
// @threat runtime
// @expect refused
// @checklist —
// @checks production-refuses
// @manifest {"capabilities": ["chat.message.send"]}
// @note The harness also asks production's grant, which must refuse the whole mount.

export default () => <Done run={async () => { note("mounted with chat.message.send asked for", "REACHED", JSON.stringify(globalThis.__spiralInit.capabilities)); }} />;
