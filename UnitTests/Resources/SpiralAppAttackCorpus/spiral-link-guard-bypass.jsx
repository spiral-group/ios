// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-link-guard-bypass
// @threat network
// @expect blocked
// @checklist —
// @note Every way round the host's link guard (F1) this pass could think of: undo it, then a non-cancelable synthetic click, a label, a slot, a key, base target, an SVG link, all detached or hidden.

export default () => <Done after={3000} run={async () => {
  const link = (tag, path, ns) => {
    const a = ns ? document.createElementNS(SVG, "a") : document.createElement(tag);
    a.setAttribute("href", CANARY + "/" + path);
    a.setAttribute("target", "_blank");
    return a;
  };
  await probe("restore HTMLElement.prototype.click", () => {
    const own = Object.getOwnPropertyDescriptor(HTMLElement.prototype, "click");
    Object.defineProperty(HTMLElement.prototype, "click", { value: function () {}, configurable: true });
    return { reached: HTMLElement.prototype.click !== own.value, detail: "redefined" };
  });
  await probe("delete EventTarget.prototype.dispatchEvent", () => ({ reached: delete EventTarget.prototype.dispatchEvent && !EventTarget.prototype.dispatchEvent, detail: "deleted" }));
  await probe("spoofed event type", () => {
    const event = new MouseEvent("click", { bubbles: true, cancelable: false });
    Object.defineProperty(event, "type", { get: () => "harmless" });
    link("a", "spoofed-type").dispatchEvent(event);
    return { info: true, detail: "dispatched" };
  });
  await attempt("non-cancelable synthetic click, detached", () => link("a", "noncancelable").dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: false })));
  await attempt("click on a child of a detached link", () => { const a = link("a", "child"); const span = document.createElement("span"); a.appendChild(span); span.click(); });
  await attempt("label forwarding into a link", () => { const label = document.createElement("label"); const a = link("a", "label"); a.appendChild(document.createElement("input")); label.appendChild(a); label.click(); });
  await attempt("dispatched click on a label holding a link", () => { const label = document.createElement("label"); const a = link("a", "label-dispatch"); a.appendChild(document.createElement("input")); label.appendChild(a); label.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: false })); });
  await attempt("dispatched click on a container holding a link", () => { const div = document.createElement("div"); div.appendChild(link("a", "container")); div.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: false })); });
  await attempt("label for, in a detached open shadow root, naming an input in a sibling link", () => {
    const host = document.createElement("div"); const root = host.attachShadow({ mode: "open" });
    const label = document.createElement("label"); label.htmlFor = "inside"; label.textContent = "x";
    const a = link("a", "label-for"); const input = document.createElement("input"); input.id = "inside"; a.appendChild(input);
    root.append(label, a); label.click();
  });
  await attempt("slot inside a shadow link", () => {
    const host = document.createElement("div"); const root = host.attachShadow({ mode: "closed" });
    const a = link("a", "slot"); a.appendChild(document.createElement("slot")); root.appendChild(a);
    const span = document.createElement("span"); host.appendChild(span); document.body.appendChild(host); span.click();
  });
  await attempt("declarative closed shadow root", () => {
    const host = document.createElement("div"); document.body.appendChild(host);
    host.setHTMLUnsafe(`<div><template shadowrootmode="closed"><a href="${CANARY}/dsd" target="_blank"><slot></slot></a></template><span></span></div>`);
    host.querySelector("span").click();
  });
  await attempt("document.write a link", () => { document.write(`<a id="w" href="${CANARY}/write" target="_blank">x</a>`); document.getElementById("w").click(); });
  await attempt("keydown Enter on a focused link", () => { const a = link("a", "enter"); document.body.appendChild(a); a.focus(); a.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", keyCode: 13, bubbles: true })); });
  await attempt("base target=_blank", () => { const base = document.createElement("base"); base.target = "_blank"; document.head.appendChild(base); const a = document.createElement("a"); a.href = CANARY + "/base"; a.click(); });
  await attempt("SVG link", () => link(null, "svg", true).dispatchEvent(new MouseEvent("click", { bubbles: true })));
  await attempt("area", () => { const area = document.createElement("area"); area.href = CANARY + "/area"; area.target = "_blank"; area.click(); });
  await attempt("prototype from Object.getPrototypeOf", () => Object.getPrototypeOf(Object.getPrototypeOf(link("a", "proto"))).click.call(link("a", "proto2")));
}} />;
