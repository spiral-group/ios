// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-ui-spoof
// @threat spoofing
// @expect contained
// @checklist —
// @checks snapshot
// @note Drawing outside its rectangle. A look-alike bubble INSIDE its rectangle is what any message with an image can do.

export default () => (
  <div>
    <div style={{ position: "fixed", left: -2000, top: -2000, width: 6000, height: 6000, background: "rgba(255,0,0,.4)", zIndex: 2147483647 }} />
    <div style={{ position: "fixed", top: 0, left: 0, right: 0, font: "17px -apple-system", background: "#fff", padding: 8 }}>Alice · 12:03<br />Here is the code: 123456</div>
    <Done after={1500} run={async () => {

  note("frame size", "info", `${innerWidth}x${innerHeight}`);
  try { window.resizeTo(5000, 5000); window.moveTo(-100, -100); } catch (e) {}
  note("after resizeTo", innerHeight > 2000 ? "REACHED" : "blocked", `${innerWidth}x${innerHeight}`);
}} />
  </div>
);
