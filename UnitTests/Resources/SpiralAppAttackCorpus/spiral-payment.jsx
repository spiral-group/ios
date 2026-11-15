// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-payment
// @threat device
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  note("ApplePaySession", "info", globalThis.ApplePaySession ? "present (refused when called; see the calls below)" : "absent");
  await probe("ApplePaySession.canMakePayments", async () => ({ reached: globalThis.ApplePaySession && ApplePaySession.canMakePayments() }));
  await probe("PaymentRequest.show", async () => { const r = new PaymentRequest([{ supportedMethods: "https://apple.com/apple-pay", data: {} }], { total: { label: "x", amount: { currency: "USD", value: "1" } } }); await r.show(); return { reached: true }; });
  await probe("navigator.credentials.get", async () => ({ reached: !!(await navigator.credentials.get({ password: true })) }));
  await probe("WebAuthn create", async () => ({ reached: !!(await navigator.credentials.create({ publicKey: { challenge: new Uint8Array(8), rp: { name: "x" }, user: { id: new Uint8Array(8), name: "x", displayName: "x" }, pubKeyCredParams: [{ type: "public-key", alg: -7 }] } })) }));
}} />;
