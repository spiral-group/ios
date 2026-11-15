// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-setattribute-src
// @threat network
// @expect blocked
// @checklist api-setattribute-src

export default () => <Done after={2000} run={async () => {

  for (const tag of ["img", "video", "audio", "source", "track", "input", "iframe", "embed"]) {
    const e = make(tag); if (tag === "input") e.setAttribute("type", "image"); e.setAttribute("src", CANARY + "/setattr-" + tag);
  }
  make("img").setAttribute("srcset", CANARY + "/setattr-srcset 1x");
}} />;
