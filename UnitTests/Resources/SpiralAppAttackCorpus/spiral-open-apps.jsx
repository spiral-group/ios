// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-open-apps
// @threat navigation
// @expect blocked
// @checklist —
// @checks shell-intact
// @wait 8000

export default () => <Done after={2000} run={async () => {

  for (const url of ["tel:+10000000000", "sms:+10000000000", "mailto:a@example.test", "facetime:a@example.test", "itms-apps://apps.apple.com/app/id1", "maps://?q=x", "shortcuts://run-shortcut?name=x", "spiral://room/!x", "matrix:u/evil:example.test", "element://x", "https://matrix.to/#/@evil:example.test", "app-settings:"]) {
    const l = make("a", { href: url }); await attempt("click " + url, () => l.click()); await settle(100);
    await attempt("location " + url, () => { location.href = url; }); await settle(100);
  }
}} />;
