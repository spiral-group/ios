// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-xhr
// @threat network
// @expect blocked
// @checklist api-xhr

export default () => <Done after={2000} run={async () => {

  await probe("xhr async", () => new Promise((resolve, reject) => {
    const x = new XMLHttpRequest(); x.open("GET", CANARY + "/xhr"); x.onload = () => resolve({ reached: true, detail: x.status });
    x.onerror = () => reject(new Error("onerror")); x.send(); }));
  await probe("xhr sync", async () => { const x = new XMLHttpRequest(); x.open("GET", CANARY + "/xhr-sync", false); x.send(); return { reached: x.status > 0, detail: x.status }; });
  await probe("xhr https", () => new Promise((resolve, reject) => {
    const x = new XMLHttpRequest(); x.open("POST", CANARY_TLS + "/xhr"); x.onload = () => resolve({ reached: true }); x.onerror = () => reject(new Error("onerror")); x.send("x"); }));
}} />;
