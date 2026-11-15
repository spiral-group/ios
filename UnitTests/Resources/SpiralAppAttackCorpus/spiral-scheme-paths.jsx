// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-scheme-paths
// @threat escape
// @expect blocked
// @checklist —
// @checks scheme-paths

export default () => <Done after={2000} run={async () => {

  const paths = ["/app.jsx", "/runtime/v1/../../shell.js", "/shell.js", "/runtime/v1/%2e%2e/%2e%2e/etc/passwd", "/index.html?x=1",
    "/runtime/v1/bootstrap.js?x", "/runtime/v2/sdk.js", "//shell/shell.js", "/Info.plist", "/../Documents/session.sqlite"];
  for (const p of paths) { make("img", { src: p }); make("script", { src: p }, document.head); }
  for (const u of ["spiral-app://shell/shell.js", "spiral-app://shell/index.html", "spiral-app://a-" + "0".repeat(64) + "/app.jsx", "spiral-app:///etc/passwd", "file:///etc/passwd", "applewebdata://x"]) { make("img", { src: u }); make("link", { rel: "stylesheet", href: u }, document.head); }
  await settle(800);
}} />;
