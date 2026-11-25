"""Run the packaged examples and check native exit receipts on one Android device."""
import argparse
import base64
import json
from io import BytesIO
from pathlib import Path
import re
import shlex
import subprocess
import time
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "org.dasrmlui.demo"


def check_frame(adb, runtime, example):
    from PIL import Image
    path = runtime + "/logs/" + example + ".png.frame7.png"
    data = subprocess.check_output(adb + ["exec-out", "run-as", PACKAGE, "cat", path], timeout=30)
    with Image.open(BytesIO(data)) as image:
        sample = image.convert("RGB").resize((160, 90), Image.Resampling.NEAREST)
        colors = sample.getcolors(sample.width * sample.height)
        if len(colors) < 16 or max(count for count, _ in colors) > .99 * sample.width * sample.height:
            raise RuntimeError(f"{example} produced an empty or nearly uniform frame ({len(colors)} colors)")
        print(f"  {example} framebuffer {image.width}x{image.height}, {len(colors)} sampled colors", flush=True)


def check_font(adb, runtime):
    from PIL import Image, ImageChops

    def mask(name, index):
        path = f"{runtime}/logs/font-{name}-{index}.png"
        data = subprocess.check_output(adb + ["exec-out", "run-as", PACKAGE, "cat", path], timeout=30)
        with Image.open(BytesIO(data)) as image:
            field = image.convert("L").crop((10, 10, 260, 100)).point(lambda value: 255 if value > 100 else 0)
            bounds = field.getbbox()
            if bounds is None:
                raise RuntimeError(f"Empty {name} glyph {index}")
            return field.crop(bounds)

    seen = set()
    for i, glyph in enumerate("ЖЯё"):
        actual, reference = mask("default", i), mask("reference", i)
        if actual.size != reference.size or ImageChops.difference(actual, reference).getbbox():
            raise RuntimeError(f"The default input font rendered {glyph!r} differently from DejaVu Sans")
        seen.add((actual.size, actual.tobytes()))
    if len(seen) != 3:
        raise RuntimeError("Distinct Cyrillic characters produced identical glyphs")
    print("  UTF-8 input preserved; Ж, Я, ё match their reference glyphs", flush=True)


def check_live_edits(adb, run, runtime):
    # Use the public watcher against isolated local files. The repository and
    # any source revisions the user already has on the phone stay intact.
    names = ("live_lab.das", "live_lab_styles.das")
    original = {}
    for name in names:
        original[name] = subprocess.check_output(
            adb + ["exec-out", "run-as", PACKAGE, "cat", f"{runtime}/examples/{name}"], timeout=20)
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        app, style = [directory / name for name in names]
        for path in (app, style):
            path.write_bytes(original[path.name])
        log = directory / "watcher.log"
        with log.open("wb") as output:
            watcher = subprocess.Popen([sys.executable, str(ROOT / "tools/android_live.py"),
                                        "--adb", adb[0], "--serial", run("get-serialno").strip(),
                                        "--examples-dir", str(directory)], stdout=output, stderr=subprocess.STDOUT)

        def wait_for(marker):
            deadline = time.monotonic() + 70
            while time.monotonic() < deadline:
                text = log.read_bytes().decode("utf-8", errors="replace")
                if marker in text:
                    return
                if watcher.poll() is not None:
                    break
                time.sleep(.4)
            raise RuntimeError(f"Watcher did not report {marker!r}:\n{text[-2000:]}")

        try:
            wait_for("[live] ready")
            pid = run("shell", "pidof", PACKAGE).strip()
            # Editors commonly save by replacing the original file.
            replacement = directory / "style.tmp"
            replacement.write_bytes(original[style.name] + "\r\n// Android stylesheet probe: Привет!\r\n".encode("utf-8"))
            replacement.replace(style)
            wait_for("[live] styles reloaded (no remount)")
            copied = subprocess.check_output(adb + ["exec-out", "run-as", PACKAGE, "cat",
                                                      f"{runtime}/examples/{style.name}"], timeout=20)
            if copied != style.read_bytes():
                raise RuntimeError("Local UTF-8 bytes or line endings changed in transit")
            app.write_bytes(original[app.name] + b"\ndef invalid_android_reload(\n")
            wait_for("compile failed; current UI kept")
            app.write_bytes(original[app.name])
            wait_for("[live] reloaded 1")
            if not pid or run("shell", "pidof", PACKAGE).strip() != pid:
                raise RuntimeError("LiveHost process changed during reload")
            print("PASS local saves reloaded the stylesheet and recovered from a script error in the same process",
                  flush=True)
        finally:
            watcher.terminate()
            watcher.wait(timeout=10)
            run("shell", "am", "force-stop", PACKAGE)
            for name, data in original.items():
                path = shlex.quote(f"{runtime}/examples/{name}")
                subprocess.run(adb + ["shell", "-T", f"run-as {PACKAGE} sh -c " + shlex.quote("base64 -d > " + path)],
                               input=base64.b64encode(data), check=True, timeout=20)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial")
    parser.add_argument("--all", action="store_true", help="run all gallery examples")
    parser.add_argument("--live-reload", action="store_true", help="edit and restore live_lab on the device")
    parser.add_argument("examples", nargs="*")
    args = parser.parse_args()
    gallery = [entry["id"] for entry in json.loads((ROOT / "web/examples.json").read_text(encoding="utf-8"))]
    available = gallery + ["android_font_input"]
    examples = available if args.all else args.examples or ["dashboard", "shader_lab", "vector_lab", "localization", "android_font_input", "live_lab"]
    if set(examples) - set(available) or (args.all and args.examples):
        parser.error("Choose gallery example IDs or --all")
    adb = [args.adb] + (["-s", args.serial] if args.serial else [])

    def run(*command):
        return subprocess.check_output(adb + list(command), text=True, encoding="utf-8", errors="replace", timeout=30)

    for example in examples:
        run("shell", "am", "force-stop", PACKAGE)
        marker = uuid.uuid4().hex
        run("shell", "log", "-t", "dasRmlUiTest", marker)
        run("shell", "am", "start", "-W", "-n", PACKAGE + "/.DemoActivity",
            "--es", "example", example, "--ez", "smoke", "true")
        deadline = time.monotonic() + 90
        while True:
            log = run("logcat", "-d", "-s", "dasRmlUiTest:I", "SDL/APP:I", "dasRmlUi:E", "AndroidRuntime:E", "libc:F")
            _, found, launch = log.rpartition(marker)
            result = re.search(r"dasRmlUi [^\r\n]*/examples/" + example + r"\.das exited with (\d+)", launch)
            if found and result and result[1] == "0":
                runtime = re.search(r"dasRmlUi runtime (/[^\s]+)", launch)
                if example in ("dashboard", "shader_lab", "vector_lab"):
                    check_frame(adb, runtime[1], example)
                elif example == "android_font_input":
                    check_font(adb, runtime[1])
                print(f"PASS {example}", flush=True)
                break
            if (found and (result or "Fatal signal" in launch or "FATAL EXCEPTION" in launch
                           or "Could not launch the example" in launch)) or time.monotonic() >= deadline:
                print(launch[-3000:] if found else "Launch marker missing from logcat", flush=True)
                runtime = re.search(r"dasRmlUi runtime (/[^\s]+)", launch)
                if runtime:
                    print(run("shell", "run-as", PACKAGE, "cat", runtime[1] + "/logs/host.log")[-5000:])
                raise SystemExit(f"FAIL {example}")
            time.sleep(0.5)
    if args.live_reload:
        check_live_edits(adb, run, runtime[1])


if __name__ == "__main__":
    main()
