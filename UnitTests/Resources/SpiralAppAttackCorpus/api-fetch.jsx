// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-fetch
// @threat network
// @expect blocked
// @checklist api-fetch

export default () => <Done after={2000} run={async () => {

  for (const url of [CANARY + "/fetch", CANARY_LOCALHOST + "/fetch", CANARY_TLS + "/fetch"]) {
    await probe("fetch " + url, async () => { const r = await fetch(url); return { reached: true, detail: r.status }; });
  }
  await probe("fetch no-cors", async () => { await fetch(CANARY + "/no-cors", { mode: "no-cors" }); return { reached: true }; });
  await probe("fetch keepalive", async () => { await fetch(CANARY + "/keepalive", { keepalive: true, method: "POST", body: "x" }); return { reached: true }; });
  await probe("Request object", async () => { await fetch(new Request(CANARY + "/request")); return { reached: true }; });
}} />;
