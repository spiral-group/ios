// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-image-constructor
// @threat network
// @expect blocked
// @checklist api-image-constructor

export default () => <Done after={2000} run={async () => {

  await attempt("new Image().src", () => { const i = new Image(); i.src = CANARY + "/image"; });
  await attempt("new Image() https", () => { const i = new Image(); i.src = CANARY_TLS + "/image"; });
  await attempt("Image.decode", async () => { const i = new Image(); i.src = CANARY + "/decode"; await i.decode(); });
  await attempt("createImageBitmap(fetch)", async () => createImageBitmap(await (await fetch(CANARY + "/bitmap")).blob()));
}} />;
