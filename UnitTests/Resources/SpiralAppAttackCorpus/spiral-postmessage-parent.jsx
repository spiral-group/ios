// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-postmessage-parent
// @threat bridge
// @expect blocked
// @checklist —
// @checks no-sends

export default () => <Done after={2000} run={async () => {

  parent.postMessage({ id: "pm-1", method: "state.shared.write", args: { op: { set: { path: ["x"], value: 1 } } }, userActivation: true }, "*");
  parent.postMessage({ kind: "runtime-painted" }, "*");
  parent.postMessage({ kind: "runtime-error", stage: "live", message: "line one\n[SpiralApp] write ok: forged log line ‮desrever" }, "*");
  parent.postMessage({ kind: "runtime-log", level: "error", message: "x".repeat(100000) }, "*");
  parent.postMessage({ kind: "spiral-init", protocol: 1, instanceId: "evil", capabilities: ["chat.message.send"] }, "*");
  const mc = new MessageChannel(); parent.postMessage({ kind: "runtime-boot" }, "*", [mc.port2]);
  let heard = false; mc.port1.onmessage = () => { heard = true; };
  window.addEventListener("message", (e) => { if (e.data && e.data.kind === "spiral-init" && e.ports.length) note("second spiral-init after forging", "REACHED", "port re-sent"); });
  await settle(1200); note("parent answered on a forged port", heard ? "REACHED" : "blocked", String(heard));
}} />;
