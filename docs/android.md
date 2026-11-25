# Android arm64

The example APK embeds the dasRmlUi interpreter host in an SDLActivity. It runs
the same daScript examples as the desktop host. The dashboard uses SDL Renderer.
The advanced examples use OpenGL ES 3.0, including the custom shader and filter
backend. Min SDK is 28 and target SDK is 35.

## Build on Windows

Use a sibling dasSDL3 checkout containing the Android port (tested revision
`2f756f5b27a26a421b7f861308b9aaf06a2fb67d`). Initialize its daScript submodule
with `git -C ../dasSDL3 submodule update --init --recursive`. Install JDK 17 or
Android Studio's JBR and the Android SDK packages below. Point `JAVA_HOME` and
`ANDROID_HOME` at the installations, or pass `-JavaHome` and `-AndroidSdk`.

```powershell
& "$env:ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager.bat" 'platform-tools' 'platforms;android-35' 'build-tools;35.0.1' 'cmake;3.31.6' 'ndk;28.2.13676358'
./tools/build_android.ps1
```

CMake builds the native libraries for `arm64-v8a`. The script stages the SDL
Java sources from the same SDL checkout, packages the scripts, fonts and
example assets, and runs that checkout's Gradle wrapper. Find the debug APK at
`build/android-apk/outputs/apk/debug/dasrmlui-debug.apk`. Use `-DasSDL3` for
a non-sibling binding checkout. `-CMakeArgs` accepts FetchContent source
overrides for offline builds with matching dependency checkouts.

## Run on a phone

Enable USB or wireless debugging, then use the serial from `adb devices -l`.
The launcher opens the interactive dashboard. Select another example with the
`example` string extra. Force-stop the previous Activity before switching.

```powershell
$adb = "$env:ANDROID_HOME/platform-tools/adb.exe"
& $adb devices -l
./tools/build_android.ps1 -Run -Serial $serial -Example dashboard
& $adb -s $serial shell am force-stop org.dasrmlui.demo
& $adb -s $serial shell am start -W -n org.dasrmlui.demo/.DemoActivity --es example shader_lab
python tests/android_device.py --adb $adb --serial $serial
python tests/android_device.py --adb $adb --serial $serial --all --live-reload
```

The Python runner uses Pillow (`python -m pip install Pillow`) to check saved
SDL and GLES frames for visible content. It launches each example in smoke
mode, waits for its native exit code and prints compiler diagnostics on
failure. The Android host loads DejaVu Sans as a fallback for Lato Latin.
The input regression enters `Привет, Ёж!` in a RmlUi field, checks its exact
value and compares the rendered shapes of `Ж`, `Я` and `ё` against the
explicit DejaVu Sans face. Smoke runs use the
existing example assertions. Examples that capture frames save their PNGs
under `logs/` inside the app's private runtime directory. Use the
`dasRmlUi runtime` line in `adb logcat -d -s SDL/APP:I` to find it. On a
debug APK, `adb shell run-as org.dasrmlui.demo` can read the files.

## Device verification

On a Redmi Note 13 running Android 15 (API 35), all 24 gallery examples passed
their smoke checks. Framebuffer readback showed visible content in the
dashboard, shader lab and vector lab at 1080 × 2400. The input test matched
three Cyrillic glyphs to their reference bitmaps. Typing Cyrillic with the phone's
keyboard also displayed the letters in the dashboard search field. LiveHost reloaded a stylesheet,
kept the active UI on a script syntax error and accepted the corrected script
in the same process.

## Live reload from your editor

Install the debug APK once, connect the phone with USB or wireless ADB, and
run the watcher from the dasRmlUi checkout. With ADB on PATH and one device connected:

```powershell
python tools/android_live.py
```

If ADB lists several devices or transports, select the serial explicitly:

```powershell
python tools/android_live.py --adb "$env:ANDROID_HOME/platform-tools/adb.exe" --serial $serial
```

The command opens **Live workbench** on the phone and synchronizes the two
local files in `examples/`. Save `live_lab.das` to change the application.
For example, edit the heading `Live workbench` in `studio`. Save
`live_lab_styles.das` to change the stylesheet. Styles update in place.
A successful code reload migrates the existing live state. A syntax error
leaves the current UI active and prints compiler diagnostics in the terminal.
Correct the file and save again to apply the next revision.

Each complete save is copied as bytes into the debug app's private runtime and
renamed into place. Ctrl+C stops synchronization. The app keeps the last
revision on the phone. Restart the command after reinstalling the APK or
reconnecting ADB. Pass `--examples-dir` to watch a separate working copy of
the two sources.
