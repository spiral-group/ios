// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack mem-huge-bitmaps
// @threat resource
// @expect contained
// @checklist mem-huge-bitmaps
// @checks liveness

export default () => <Done after={1000} run={async () => {

  const sizes = [[16384, 16384], [8192, 8192], [4096, 4096]]; const keep = [];
  for (const [w, h] of sizes) { try { const c = document.createElement("canvas"); c.width = w; c.height = h; const g = c.getContext("2d"); g.fillRect(0, 0, w, h); keep.push(g.getImageData(0, 0, Math.min(w, 4096), Math.min(h, 4096))); note(`canvas ${w}x${h}`, "info", g ? "context" : "no context"); } catch (e) { note(`canvas ${w}x${h}`, "info", describe(e)); } }
  try { for (let i = 0; i < 8; i++) keep.push(await createImageBitmap(new ImageData(4096, 4096))); note("image bitmaps", "info", "8 x 64 MB"); } catch (e) { note("image bitmaps", "info", describe(e)); }
  globalThis.__keep = keep;
}} />;
