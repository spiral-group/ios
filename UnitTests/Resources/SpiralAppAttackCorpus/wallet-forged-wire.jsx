// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack wallet-forged-wire
// @threat activation
// @expect refused
// @checklist wallet-forged-wire
// @checks no-expand no-mentions
// @note Analogue: the frame's own userActivation is dropped natively (SpiralAppInstance), so forging it buys nothing.

export default () => <Done after={2000} run={async () => {

  const people = await call("members.basic.read", null);
  const everyone = ((people.data && people.data.members) || []).map((m) => m.userId);
  const pingAll = (line) => ({ op: { incr: { path: ["n"], by: 1 } }, summary: { line, notify: "ping", notify_users: [...everyone, "@stranger:elsewhere.test"] } });
  const realStringify = JSON.stringify; JSON.stringify = (v) => realStringify(v).replace('"userActivation":false', '"userActivation":true');
  __port.postMessage({ id: "forged-1", method: "ui.expand", args: null, userActivation: true });
  __port.postMessage({ id: "forged-2", method: "state.shared.write", args: pingAll("forged wire"), userActivation: true, touched: true, activation: { recent: true } });
  await settle(800); JSON.stringify = realStringify;
}} />;
