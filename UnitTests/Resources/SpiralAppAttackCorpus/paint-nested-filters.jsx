// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack paint-nested-filters
// @threat resource
// @expect contained
// @checklist paint-nested-filters
// @checks liveness

export default () => (
  <div>
    <style>{`.p{filter:blur(4px)} .p .p{filter:blur(8px)}`}</style>
    {Array.from({ length: 1 }, (_, i) => <div key={i} className="p"><div className='p'><div className='p'><div className='p'>deep</div></div></div></div>)}
    <Done after={4000} />
  </div>
);
