// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-dns-named-https
// @threat network
// @expect blocked
// @checklist —
// @wait 9000
// @note Device pass: a host NAME over https (App Transport Security refuses plain http to a name before any lookup). On a device each label.localhost becomes label.example.com, so a lookup would leave the phone; the witness is the packet capture, beside control-dns-plain-webview.

export default () => <Done after={4000} run={async () => {

  const name = (label) => `spiral-dns-${label}-0123abcd.localhost`;
  await attempt("_blank link, https name", () => make("a", { href: `https://${name("blank")}/x`, target: "_blank" }).click());
  await attempt("_blank link, https name, noopener", () => make("a", { href: `https://${name("noopener")}/x`, target: "_blank", rel: "noopener noreferrer" }).click());
  await attempt("img https name", () => { make("img", { src: `https://${name("img")}/x.png` }); });
  await attempt("fetch https name", () => fetch(`https://${name("fetch")}/x`).catch((e) => describe(e)));
  await attempt("link dns-prefetch", () => { make("link", { rel: "dns-prefetch", href: `https://${name("prefetch")}` }, document.head); });
  await attempt("link preconnect", () => { make("link", { rel: "preconnect", href: `https://${name("preconnect")}` }, document.head); });
  await attempt("WebSocket wss name", () => { try { new WebSocket(`wss://${name("wss")}/x`); } catch (e) { return describe(e); } });
  await attempt("CSS url https name", () => { make("div", { style: `background:url(https://${name("css")}/x.png);width:10px;height:10px` }); });
}} />;
