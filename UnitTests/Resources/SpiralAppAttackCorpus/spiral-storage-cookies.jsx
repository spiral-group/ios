// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-storage-cookies
// @threat persistence
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  await probe("localStorage", async () => { localStorage.setItem("k", MARKER); return { reached: localStorage.getItem("k") === MARKER }; });
  await probe("sessionStorage", async () => { sessionStorage.setItem("k", MARKER); return { reached: sessionStorage.getItem("k") === MARKER }; });
  await probe("document.cookie", async () => { document.cookie = "k=" + MARKER; return { reached: document.cookie.includes(MARKER), detail: document.cookie }; });
  await probe("indexedDB", () => new Promise((resolve, reject) => { const r = indexedDB.open("x"); r.onsuccess = () => resolve({ reached: true }); r.onerror = () => reject(r.error); setTimeout(() => reject(new Error("no answer")), 1000); }));
  await probe("CacheStorage", async () => { const c = await caches.open("x"); return { reached: !!c }; });
  await probe("openDatabase", async () => ({ reached: typeof openDatabase === "function" && !!openDatabase("x", "1", "x", 1) }));
  await probe("storage.estimate", async () => { const e = await navigator.storage.estimate(); return { reached: true, detail: JSON.stringify(e) }; });
  await probe("storage.getDirectory (OPFS)", async () => ({ reached: !!(await navigator.storage.getDirectory()) }));
  await probe("cookieStore", async () => { await cookieStore.set("k", MARKER); return { reached: true }; });
}} />;
