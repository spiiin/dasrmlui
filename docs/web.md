# Browser build and example gallery

The static gallery lists all 24 examples with real UI screenshots, search and category
filters. A card opens `example.html?demo=<id>` and runs its daScript component code in
WebAssembly through SDL3 and RmlUi's WebGL 2 backend. There is no server-side runtime.

## Build

Requirements: Emscripten **5.0.3**, CMake 3.24+, Ninja, Python 3, the same daScript
checkout used by dasSDL3, a wasm32 SDL3 build from `dasSDL3/web`, FreeType sources,
and the pinned RmlUi checkout used by the native build. daScript is compiled from
source in this build; stale prebuilt compiler archives are deliberately not reused.
The SVG/Lottie dependencies use the same pins as the native build.

From the repository root, after building `dasSDL3/web`:

```powershell
./tools/build_web.ps1 -Emsdk C:/src/emsdk `
  -SdlDir C:/src/dasSDL3 `
  -RmlDir C:/src/dascript_sdl_gui/third_party/RmlUi `
  -FreeTypeSource C:/path/to/freetype
python -m http.server 8766 --bind 127.0.0.1 --directory build/web/site
```

Open <http://127.0.0.1:8766/>. If Ninja is not on PATH, pass
`-CMakeArgs '-DCMAKE_MAKE_PROGRAM=C:/path/to/ninja.exe'`. An existing build remembers
its FreeType/source paths. `-BuildDir` selects a separate output tree.
For offline builds, `-CMakeArgs` also accepts `-DFETCHCONTENT_SOURCE_DIR_LUNASVG=...`
and `-DFETCHCONTENT_SOURCE_DIR_RLOTTIE=...` pointing to the native build's sources.

The output `build/web/site` is a self-contained static directory. Serve `.wasm` as
`application/wasm`; HTTP compression is recommended. Do not open `index.html` via
`file://`: resources are loaded with fetch. All links are relative, so a deployment
under a URL prefix works. No CDN, external fonts or service worker is required.

## Browser/runtime profile

This profile needs WebGL 2, WebAssembly SIMD, Wasm exceptions and **JSPI**. The player
checks JSPI before downloading the engine and explains unsupported browsers. Use a
current Chrome/Edge with JSPI support. Other browsers must expose
`WebAssembly.Suspending`; a generic WebAssembly-capable browser is not sufficient.

JSPI suspends the ordinary daScript main loop at frame boundaries, keeping its
stack-bound closures alive. Traditional Asyncify conflicts with native Wasm
exception handling in this toolchain. See [Emscripten asynchronous code](https://emscripten.org/docs/porting/asyncify.html).

`web/examples/demo_host.das` and `gl_demo_host.das` replace only desktop window/event
loops in the staged VFS. Components/styles remain the original files. Inventory has
an equivalent small browser entry point. RmlUi uses the GL3 renderer's GLES branch;
custom shader/filter source uses GLSL ES 300. The staged localization example uses
bundled DejaVu Sans instead of a Windows system font. Host adapters retain periodic
script GC.

Live workbench runs the real LiveHost against the browser VFS. Its Reload/Reset
buttons preserve/reset state as on desktop; watching physical disk files requires
the desktop host. Browser navigation/restart starts a fresh runtime and does not
persist state across pages. Large examples compile on first launch and can take a
few seconds. The gallery itself never downloads the Wasm engine.

## Screenshots and checks

```powershell
./tools/capture_web_gallery.ps1
./tools/build_web.ps1 # stage updated screenshots and scripts
python tests/web/test_browser.py
# Or a focused pass:
python tests/web/test_browser.py --only catalog,shader_lab,live_lab
```

Capture uses the native Windows renderer and the existing smoke entry points. Images
are versioned in `web/assets/screenshots`; LiveHost uses a temporary fixture under
`build/web`. Browser tests require `playwright`, Pillow and Microsoft Edge. They
check all gallery links/images, search, categories, desktop/mobile layout, actual
WebGL pixels, runtime errors, clean shutdown and invalid routes. Dashboard also
checks pointer clicks, text input and resize; LiveHost checks reload with an edited
state value. Test screenshots
are written to `logs/web`.

## GitHub Actions

`.github/workflows/web.yml` runs on pushes, pull requests and manual dispatches.
It builds on Ubuntu 24.04 with Emscripten 5.0.3, then tests all 24 examples in
Chromium using software WebGL. The downloadable **dasrmlui-web** artifact contains
the complete `site/` contents. **web-test-results** includes screenshots and logs,
also on a failed test run.

## GitHub Pages

The public gallery is at **https://spiiin.github.io/dasrmlui/**.
`.github/workflows/pages.yml` automatically publishes the latest successful
`Web gallery` artifact from this repository's `master` branch after tests pass.
Failed builds, pull requests and fork builds cannot publish. Publication reuses
the tested static artifact; it does not rebuild or execute artifact contents.
Manual **Run workflow** on **Publish GitHub Pages** republishes the latest
successful build, which is useful for retrying a failed deployment.

Repository **Settings → Pages → Build and deployment → Source** is set to
**GitHub Actions**. The deploy job uses the `github-pages` environment and grants
`pages: write` and `id-token: write` only to that job; artifact download gets
`actions: read`. Deployments are serialized and do not interrupt one another.
The gallery uses relative links, so images, scripts, Wasm and data files work
under the `/dasrmlui/` project prefix. No custom domain or external CDN is needed.

### Reproducible build

Source revisions are pinned in `web/dependencies.json`. `tools/fetch_web_deps.py`
fetches them into an isolated directory and refuses modified dependency checkouts.
SVG/Lottie revisions remain pinned in `cmake/vector_plugins.cmake`.
CI uses `-DSDL3_SOURCE=...` to build SDL3 in the same tree, so no prebuilt SDK,
Windows paths, tokens or private dependencies are required. The build workflow only reads repository contents; publishing permissions are
scoped to the separate Pages workflow.

The same source-only configure is available locally:

```sh
python tools/fetch_web_deps.py --destination build/web-deps
emcmake cmake -S web -B build/web-ci -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DDASSDL3_DIR="$PWD/build/web-deps/dasSDL3" \
  -DRMLUI_DIR="$PWD/build/web-deps/RmlUi" \
  -DSDL3_SOURCE="$PWD/build/web-deps/SDL" \
  -DFREETYPE_SOURCE="$PWD/build/web-deps/freetype"
python tools/prepare_web.py --build build/web-ci --sdl build/web-deps/dasSDL3 --rml build/web-deps/RmlUi
cmake --build build/web-ci --parallel 2
```

For Chromium tests install `tests/web/requirements.txt`, run
`python -m playwright install --with-deps chromium`, serve the output, and use
`python tests/web/test_browser.py --browser chromium --software-gl`.
