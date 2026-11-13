# SVG/Lottie dependencies

`cmake/vector_plugins.cmake` enables the official RmlUi plugins and statically builds:

| Library | Pinned revision | License |
|---|---|---|
| LunaSVG 3.2.1 | `f8aabfb444bb37f69df7290790f57e4a27730a93` | MIT |
| PlutoVG | submodule pinned by LunaSVG | MIT |
| Samsung rlottie | `ea06d2f29ba01b8d06c00a838d107f5e484ae59b` | MIT; third-party files have their own notices |

The first `./tools/build.ps1` run needs Git and network access for FetchContent.
Sources, licenses and build outputs are stored under `build/_deps`; the existing RmlUi
and dasSDL3 checkouts are not modified. When you distribute a binary, keep the
LICENSE/COPYING files and notices of these dependencies, including the nested
third-party files of rlottie.

`patch_rlottie.cmake` patches only the fetched build copy: it raises the minimum
CMake version from 3.3 to 3.15 and removes the forced `/MT`, so that all libraries use
the same `/MD` CRT. `renderSync` works without background threads; the external
image-loader DLL is disabled. The lottie2gif utility is not part of the regular build.

For an offline configure you can pass `FETCHCONTENT_SOURCE_DIR_LUNASVG` (with the
PlutoVG submodule populated) and `FETCHCONTENT_SOURCE_DIR_RLOTTIE`. CMake skips
PATCH_COMMAND with such an override: use a prepared build copy, or apply
`cmake -DSOURCE_DIR=<rlottie-copy> -P cmake/patch_rlottie.cmake` to a separate copy
beforehand.

The SVG/JSON files in `examples/assets/vector_*` are original geometric drawings of
this project. They are reproduced with `python tools/make_vector_assets.py` and do not
require downloading third-party illustrations. The probe assets are meant for
deterministic tests; flower/orbit/motion/pulse are for the interactive example.

Native API: [SVG](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/svg.html),
[Lottie](https://mikke89.github.io/RmlUiDoc/pages/cpp_manual/lottie.html).
