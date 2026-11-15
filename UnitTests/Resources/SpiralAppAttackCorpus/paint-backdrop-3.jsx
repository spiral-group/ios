// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack paint-backdrop-3
// @threat resource
// @expect contained
// @checklist paint-backdrop-3
// @checks liveness

export default () => (
  <div>
    <style>{`.p{position:absolute;inset:0;backdrop-filter:blur(60px) saturate(4);-webkit-backdrop-filter:blur(60px)}`}</style>
    {Array.from({ length: 3 }, (_, i) => <div key={i} className="p">x</div>)}
    <Done after={4000} />
  </div>
);
