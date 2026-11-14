# dasrmlui Inventory for iPhone

This profile builds an arm64 iPhone app using SDL 3.4.16 through dasSDL3 and the
existing RmlUi SDL_Renderer backend. The app bundles the script runtime,
Inventory components, LatoLatin, and DejaVu Sans for Cyrillic fallback. It executes scripts in the interpreter
and uses SDL app callbacks for rendering, input and background/foreground events.

Use Xcode, CMake 3.24 or later, dasSDL3 at
`7639a616fc9b2721d7b1887057d6bac1cc881cef` with its daScript submodule
initialized, and the RmlUi revision listed in the main README. For FreeType
use 2.14.3. Configure from the dasrmlui checkout:

```sh
cmake -S ios -B build/iphone -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DDASSDL3_DIR=/path/to/dasSDL3 -DRMLUI_DIR=/path/to/RmlUi \
  -DFREETYPE_SOURCE=/path/to/freetype \
  -DDASRMLUI_IOS_BUNDLE_ID=com.example.inventory \
  -DDASRMLUI_IOS_TEAM=YOUR_TEAM_ID
cmake --build build/iphone --config Release --target dasrmlui_iphone
```

Set the bundle identifier and team to match your development signing profile.
Open the generated Xcode project and run the `dasrmlui_iphone` scheme on an
iPhone with Developer Mode enabled. In Inventory you can add, edit and remove
items. Launch with `--smoke-test` to exercise SDL/RmlUi hit testing, verify that
the model gains an item, and send Latin and Cyrillic SDL text events while
checking that the on-screen keyboard stays visible.

```sh
xcrun devicectl device process launch --device DEVICE_ID --console \
  --terminate-existing com.example.inventory -- --smoke-test
```

## Native Lab

Pass `--native-lab` to open Signal Foundry. The compact layout reuses the
desktop example's daScript-defined waveform element. Tap the trace to select
it, then use **Hold trace** to pause the animation. Add `--smoke-test` to
check selection, pause and the rendered waveform on the phone.

GitHub Actions builds the unsigned `iphoneos` application and checks the
arm64 binary and its bundled resources. The interactive tests run on an
iPhone.
