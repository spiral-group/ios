// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-importscripts
// @threat network
// @expect blocked
// @checklist api-importscripts
// @note No window has importScripts; only a worker would, and worker-src 'none' refuses one.

export default () => <Done after={2000} run={async () => {

  exists("importScripts in the window", globalThis.importScripts);
  await probe("importScripts via a worker", async () => {
    const w = new Worker(URL.createObjectURL(new Blob(["importScripts('" + CANARY + "/import-scripts')"])));
    return { info: true, detail: w ? "constructor returned; the load is the canary's to see" : "no worker" }; });
}} />;
