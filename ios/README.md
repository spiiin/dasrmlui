# dasrmlui examples for iPhone

The arm64 app runs the same example scripts as the desktop host. It
bundles the daScript runtime, the examples, their assets and fonts.
The common window hosts use SDL Renderer or OpenGL ES on iOS.

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
Install the resulting app from Xcode on an iPhone with Developer Mode enabled.
It opens Inventory by default. Use `--example` to select a script by its name:

```sh
xcrun devicectl device process launch --device DEVICE_ID --terminate-existing \
  com.example.inventory -- --example native_lab
```

Add `--console` before the bundle identifier and `--smoke-test` after the
example name to run the script's desktop smoke checks and see its exit status.
The app writes smoke screenshots to `Library/Application Support/dasrmlui/Examples/logs`
in its data container. Live Lab uses the bundled stylesheet. The smoke run
checks its startup and frame loop. The signed bundle is read-only on the device.

### Live Workbench on a connected iPhone

Launch Live Workbench with `--live-edit` so it watches writable copies of
`live_lab.das` and `live_lab_styles.das` in its data container. The first launch
copies the bundled scripts there, and subsequent launches keep your edits.

```sh
xcrun devicectl device process launch --device DEVICE_ID --terminate-existing \
  --console com.example.inventory -- --example live_lab --live-edit
```

Enter a title in the app. From the checkout, start the Mac watcher in a second
terminal. It sends the selected files once on startup and again when you save
changes:

```sh
python3 tools/watch_ios_live.py --device DEVICE_ID --bundle-id com.example.inventory \
  examples/live_lab.das examples/live_lab_styles.das
```

Change the heading in `live_lab.das` and save. The heading should change on the
iPhone, the title you entered should remain, and the console should report
`[live] reloaded 1` (or a higher generation if it has already reloaded). A
stylesheet save reports `[live] styles reloaded (no remount)`. Stop the Mac
watcher with Ctrl+C. The phone keeps the latest copies in
`Library/Application Support/dasrmlui/LiveWorkbench`. To restore the bundled
UI in edit mode, sync the original scripts from the checkout.

GitHub Actions builds the unsigned `iphoneos` app and checks the arm64 binary
and bundled scripts. Smoke tests run on a physical iPhone.
