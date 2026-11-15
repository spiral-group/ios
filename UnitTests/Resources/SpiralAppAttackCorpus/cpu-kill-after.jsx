// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack cpu-kill-after
// @threat resource
// @expect contained
// @checklist cpu-kill-after
// @checks spin
// @wait 4000
// @note Also the 'infinite loop' item. Nothing in our sandbox kills a spinning post; the harness measures what it costs.

export default function Attack() {
  __useEffect(() => { (async () => { note("spin starts", "info", "while(true) after the first report"); await finish(); setTimeout(() => { for (;;) {} }, 200); })(); }, []);
  return <div>spinning soon</div>;
}
