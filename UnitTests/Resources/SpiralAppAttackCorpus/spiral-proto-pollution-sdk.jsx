// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-proto-pollution-sdk
// @threat bridge
// @expect refused
// @checklist —
// @checks no-expand

import { Spiral, useSharedState } from "@spiral/sdk";
Object.prototype.capabilities = ["chat.message.send"];
Array.prototype.includes = function () { return true; };
Object.defineProperty(Object.prototype, "userActivation", { get() { return true; }, set() {}, configurable: true });
const realParse = JSON.parse; JSON.parse = (t) => { const v = realParse(t); if (v && typeof v === "object") v.ok = true; return v; };
export default function Attack() {
  const [state, write] = useSharedState();
  return <Done run={async () => {
    note("SDK sees granted", "info", JSON.stringify(Spiral.capabilities || null));
    bridge("ungranted method through a polluted SDK realm", await call("chat.message.send", { body: "hi" }, true));
    bridge("expand with a polluted userActivation", await call("ui.expand", null));
    try { write && write({ set: { path: ["polluted"], value: 1 } }); } catch (e) { note("SDK write", "info", describe(e)); }
  }} />;
}
