// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-dynamic-import-literal
// @threat network
// @expect compile-refused
// @checklist api-dynamic-import
// @note The import allow-list in transpile.ts refuses a non-allow-listed specifier at compile time.

export default function Attack() {
  import("http://127.0.0.1:47913/c/api-dynamic-import-literal/literal");
  return null;
}
