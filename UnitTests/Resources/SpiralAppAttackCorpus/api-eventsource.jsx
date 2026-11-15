// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-eventsource
// @threat network
// @expect blocked
// @checklist api-eventsource

export default () => <Done after={2000} run={async () => {

  exists("EventSource constructor", globalThis.EventSource);
  await probe("new EventSource", () => new Promise((resolve, reject) => {
    const s = new EventSource(CANARY + "/es"); s.onopen = () => resolve({ reached: true }); s.onerror = () => reject(new Error("onerror")); setTimeout(() => reject(new Error("no open")), 1500); }));
}} />;
