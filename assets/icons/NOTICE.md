# MingCute icon assets

`sun.svg` and `full-moon.svg` are adapted from the MingCute Icons Core Regular
set at commit `ca98bb55513a22ff0dab713aaf7870b512944653`.

- Source: <https://github.com/mingcute-design/mingcute-icons>
- Original sun: `packages/svg/core-regular/sun.svg`
- Original full moon: `packages/svg/core-regular/full-moon.svg`
- License: Apache License 2.0; see `LICENSE.txt` in this directory.

The only change is replacing `currentColor` with white so Qt can rasterize the
SVGs as stable masks. The plugin applies the active Omarchy foreground color at
runtime.
