// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-worker
// @threat network
// @expect blocked
// @checklist api-worker

export default () => <Done after={2000} run={async () => {

  await probe("Worker from blob", async () => { const w = new Worker(URL.createObjectURL(new Blob(["fetch('" + CANARY + "/worker')"]))); return { info: true, detail: w ? "constructor returned; the load is the canary's to see" : "no worker" }; });
  await probe("Worker from data:", async () => { const w = new Worker("data:text/javascript,fetch('" + CANARY + "/worker-data')"); return { info: true, detail: w ? "constructor returned; the load is the canary's to see" : "no worker" }; });
  await probe("Worker from the canary", async () => { const w = new Worker(CANARY + "/worker.js"); return { info: true, detail: w ? "constructor returned; the load is the canary's to see" : "no worker" }; });
  await probe("SharedWorker", async () => { const w = new SharedWorker(URL.createObjectURL(new Blob(["1"]))); return { info: true, detail: w ? "constructor returned; the load is the canary's to see" : "no worker" }; });
  await settle(500);
}} />;
