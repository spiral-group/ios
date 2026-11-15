// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack paint-animation-17
// @threat resource
// @expect contained
// @checklist paint-animation-17
// @checks liveness

export default () => (
  <div>
    <style>{`@keyframes g{50%{opacity:.2;filter:blur(18px)}} .p{width:60px;height:60px;display:inline-block;background:#f0f;box-shadow:0 0 40px 20px #0ff;animation:g .2s infinite}`}</style>
    {Array.from({ length: 17 }, (_, i) => <div key={i} className="p">x</div>)}
    <Done after={4000} />
  </div>
);
