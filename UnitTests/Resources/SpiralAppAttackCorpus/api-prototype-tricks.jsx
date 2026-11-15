// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-prototype-tricks
// @threat network
// @expect blocked
// @checklist api-prototype-tricks

export default () => <Done after={2000} run={async () => {

  const srcSetter = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, "src").set;
  await attempt("src setter from the prototype", () => srcSetter.call(new Image(), CANARY + "/proto-src"));
  await attempt("Element.prototype.setAttribute via Reflect", () => Reflect.apply(Element.prototype.setAttribute, make("img"), ["src", CANARY + "/reflect"]));
  await attempt("fetch from the Window prototype", () => Window.prototype.fetch ? Window.prototype.fetch.call(window, CANARY + "/proto-fetch") : undefined);
  await attempt("XHR open restored", () => { const o = XMLHttpRequest.prototype.open; const x = new XMLHttpRequest(); o.call(x, "GET", CANARY + "/proto-xhr"); x.send(); });
  Object.defineProperty(Object.prototype, "src", { configurable: true, set() {}, get() { return CANARY + "/proto-pollute"; } });
  make("img", {}); await settle(300); delete Object.prototype.src;
}} />;
