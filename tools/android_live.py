"""Watch the live_lab example on this computer and update it on an Android device."""
import argparse
import base64
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "org.dasrmlui.demo"
FILES = ("live_lab.das", "live_lab_styles.das")


def launch(adb):
    marker = uuid.uuid4().hex
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "log", "-t", "dasRmlUiWatch", marker)
    adb("shell", "am", "start", "-W", "-n", PACKAGE + "/.DemoActivity", "--es", "example", "live_lab")
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        log = adb("logcat", "-b", "main", "-d", "-s", "dasRmlUiWatch:I", "SDL/APP:I").decode(errors="replace")
        match = re.search(r"dasRmlUi runtime (/\S+)", log.partition(marker)[2])
        if match:
            return match[1]
        time.sleep(.4)
    raise RuntimeError("LiveHost did not start. Check that the debug APK is installed and the device is unlocked.")


def watch(adb, directory):
    paths = [directory / name for name in FILES]
    # Fail before switching the phone to live_lab if a local input is missing.
    previous = {p: p.read_bytes() for p in paths}
    runtime = launch(adb)
    print(f"Watching {directory} ({', '.join(FILES)})", flush=True)
    session = uuid.uuid4().hex
    sent = {p: adb("exec-out", "run-as", PACKAGE, "cat", f"{runtime}/examples/{p.name}") for p in paths}
    log_path = runtime + "/logs/host.log"
    offset = 0
    read_until = time.monotonic() + 60
    next_read = 0
    ready = False
    exited = False
    while True:
        now = time.monotonic()
        if now >= next_read and now < read_until:
            output = adb("exec-out", "run-as", PACKAGE, "tail", "-c", f"+{offset + 1}", log_path)
            offset += len(output)
            if output:
                message = output.decode("utf-8", errors="replace")
                print(message, end="", flush=True)
                ready |= "[live] ready" in message
                exited |= " exited with " in message
            next_read = now + .8
        if not ready and not exited and now >= read_until:
            raise RuntimeError("Timed out waiting for the LiveHost startup result.")

        changed = False
        for path in paths:
            try:
                data = path.read_bytes()
            except (FileNotFoundError, PermissionError):
                # Editors may briefly remove or lock the old file while saving.
                previous.pop(path, None)
                continue
            stable = previous.get(path) == data
            previous[path] = data
            if (not ready and not exited) or not stable or sent[path] == data:
                continue
            remote = f"{runtime}/examples/{path.name}"
            temp = shlex.quote(remote + "." + session + ".tmp")
            # Windows adb shell can translate CRLF on stdin. Transport ASCII
            # and decode inside the private directory before publishing.
            command = f"base64 -d > {temp} && mv {temp} {shlex.quote(remote)}"
            adb("shell", "-T", "run-as " + PACKAGE + " sh -c " + shlex.quote(command), data=base64.b64encode(data))
            sent[path] = data
            changed = True
            print(f"Saved to Android: {path.name}", flush=True)

        if changed:
            # An invalid on-device entry can fail at cold start. Its next edit
            # must start the Activity again; normal live edits keep the window.
            if exited:
                if launch(adb) != runtime:
                    raise RuntimeError("The APK changed. Restart the watcher to select its new runtime.")
                offset = 0
                ready = exited = False
            read_until = time.monotonic() + 60
            next_read = 0
        time.sleep(.25)


def main():
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    default_adb = shutil.which("adb") or (str(Path(sdk) / "platform-tools" / "adb") if sdk else "adb")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default=default_adb, help="path to Android SDK adb")
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL"), help="device shown by adb devices")
    parser.add_argument("--examples-dir", type=Path, default=ROOT / "examples", help="directory with both live_lab sources")
    args = parser.parse_args()
    device = [args.adb] + (["-s", args.serial] if args.serial else [])
    # Pin the transport even when ADB auto-selects the only connected device.
    serial = subprocess.check_output(device + ["get-serialno"], timeout=15).decode().strip()
    if not serial or serial == "unknown":
        raise RuntimeError("Select a connected device with --serial.")
    print("Android device:", serial, flush=True)

    def adb(*command, data=None):
        return subprocess.run([args.adb, "-s", serial, *command], input=data, stdout=subprocess.PIPE,
                              check=True, timeout=30).stdout

    watch(adb, args.examples_dir.resolve())


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
