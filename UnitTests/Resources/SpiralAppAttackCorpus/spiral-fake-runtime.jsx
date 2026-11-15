// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-fake-runtime
// @threat runtime
// @expect refused
// @checklist —
// @checks mount-refused
// @manifest {"runtime": "99"}
// @note A newer runtime claim should be refused or shown as 'update the app', not run under v1.

export default () => <Done after={2000} run={async () => {

  note("mounted although the manifest says runtime 99", "REACHED", JSON.stringify(globalThis.__spiralInit && globalThis.__spiralInit.runtimeVersion));
}} />;
