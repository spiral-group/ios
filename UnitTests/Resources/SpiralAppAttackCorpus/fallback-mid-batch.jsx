// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack fallback-mid-batch
// @threat resource
// @expect contained
// @checklist fallback-mid-batch
// @checks spin snapshot
// @wait 4000

export default function Attack() {
  __useEffect(() => { (async () => { await finish(); setTimeout(() => { document.body.innerHTML = "<h1 style='font:40px sans-serif'>HALF</h1>"; for (;;) {} }, 300); })(); }, []);
  return <div style={{ font: "40px sans-serif" }}>BEFORE</div>;
}
