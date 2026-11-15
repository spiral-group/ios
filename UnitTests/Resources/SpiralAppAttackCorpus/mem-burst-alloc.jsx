// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack mem-burst-alloc
// @threat resource
// @expect contained
// @checklist mem-burst-alloc
// @checks liveness

export default () => <Done after={1000} run={async () => {

  const keep = []; let mb = 0;
  try { for (; mb < 1536; mb += 64) { const b = new Uint8Array(64 * 1024 * 1024); for (let i = 0; i < b.length; i += 4096) b[i] = 1; keep.push(b); } note("burst allocation", "info", `${mb} MB held`); }
  catch (e) { note("burst allocation", "info", `${mb} MB then ${describe(e)}`); }
  globalThis.__keep = keep;
}} />;
