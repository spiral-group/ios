// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack paint-ars
// @threat resource
// @expect contained
// @checklist paint-ars
// @checks liveness

import { useEffect, useState } from "react";
export default function Attack() {
  const [t, setT] = useState(0);
  useEffect(() => { let id; const step = () => { setT((v) => v + 1); id = requestAnimationFrame(step); }; id = requestAnimationFrame(step); setTimeout(() => cancelAnimationFrame(id), 5000); }, []);
  return (<div>{Array.from({ length: 3000 }, (_, i) => <i key={i} style={{ position: "absolute", left: (i * 7 + t) % 360, top: (i * 13 + t) % 400, width: 6, height: 6, background: `hsl(${(i + t) % 360},90%,50%)`, transform: `rotate(${t + i}deg)` }} />)}<Done after={5500} /></div>);
}
