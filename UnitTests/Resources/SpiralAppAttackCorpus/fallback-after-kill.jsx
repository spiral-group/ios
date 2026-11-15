// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack fallback-after-kill
// @threat resource
// @expect contained
// @checklist fallback-after-kill
// @checks spin snapshot
// @wait 4000
// @note Holds about 1 GB, then spins. The first run grew without a bound and took the Mac's swap to 34 GB before the simulator was shut.

export default function Attack() {
  __useEffect(() => { (async () => { note("drew, then hangs", "info", ""); await finish(); setTimeout(() => { const a = []; for (;;) { if (a.length < 1200) a.push(new Array(1e5).fill(1)); } }, 300); })(); }, []);
  return <div style={{ font: "40px sans-serif", background: "#fc0", height: "100%" }}>LAST FRAME</div>;
}
