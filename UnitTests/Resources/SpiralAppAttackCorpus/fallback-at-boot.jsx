// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack fallback-at-boot
// @threat resource
// @expect contained
// @checklist fallback-at-boot
// @checks spin boot-hang
// @wait 12000

for (;;) {}
export default () => null;
