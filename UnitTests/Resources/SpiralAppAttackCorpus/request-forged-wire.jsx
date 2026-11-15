// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack request-forged-wire
// @threat bridge
// @expect refused
// @checklist request-forged-wire
// @checks no-sends

export default () => <Done after={2000} run={async () => {

  const raw = (message) => { try { __port.postMessage(message); } catch (e) { note("post " + JSON.stringify(message).slice(0, 40), "info", describe(e)); } };
  for (const method of ["chat.message.send", "media.read", "agent.run", "messages.read", "members.full.read", "__proto__", "constructor", "state.shared.write ", "STATE.SHARED.WRITE"]) {
    bridge("ungranted or unknown method " + method, await call(method, {}, true, undefined, 800));
  }
  raw({ id: "x1", method: "state.shared.write", args: { op: { set: { path: ["a"], value: 1 } } } });
  raw({ id: "", method: "app.context.read", userActivation: true });
  raw({ method: "app.context.read", userActivation: true });
  raw({ id: { toString() { return "x"; } }, method: "app.context.read", userActivation: true });
  raw("app.context.read"); raw(null); raw([1, 2]); raw(new ArrayBuffer(8));
  const mc = new MessageChannel(); try { __port.postMessage({ id: "p", method: "app.context.read", userActivation: true }, [mc.port2]); } catch (e) {}
  note("duplicate id answered twice? (two calls race on one id in the harness)", "info", JSON.stringify(await Promise.race([call("app.context.read", null, false, "dup"), call("app.context.read", null, false, "dup")])));
  await settle(800);
}} />;
