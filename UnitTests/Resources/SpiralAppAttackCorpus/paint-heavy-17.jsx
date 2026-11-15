// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack paint-heavy-17
// @threat resource
// @expect contained
// @checklist paint-heavy-17
// @checks liveness

export default () => (
  <div>
    <style>{`.p{width:120px;height:120px;display:inline-block;filter:blur(30px) drop-shadow(0 0 40px red) saturate(3);box-shadow:0 0 80px 60px rgba(0,0,0,.5),inset 0 0 60px #00f;border-radius:50%}`}</style>
    {Array.from({ length: 17 }, (_, i) => <div key={i} className="p">x</div>)}
    <Done after={4000} />
  </div>
);
