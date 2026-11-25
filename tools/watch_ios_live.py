#!/usr/bin/env python3
"""Send saved Live Workbench scripts to a running iPhone app."""

import argparse
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="iPhone identifier")
    parser.add_argument("--bundle-id", required=True, help="Installed app's bundle ID")
    parser.add_argument("scripts", nargs="+", type=Path)
    args = parser.parse_args()
    names = {script.name for script in args.scripts}
    if len(names) != len(args.scripts) or not names <= {"live_lab.das", "live_lab_styles.das"}:
        parser.error("Specify live_lab.das or live_lab_styles.das at most once each.")

    destination = "Library/Application Support/dasrmlui/LiveWorkbench"
    copy = [
        "xcrun", "devicectl", "device", "copy", "to", "--device", args.device,
        "--domain-type", "appDataContainer", "--domain-identifier", args.bundle_id, "--timeout", "10",
    ]
    sent = {}
    with tempfile.TemporaryDirectory() as temporary:
        while True:
            for script in args.scripts:
                try:
                    data = script.read_bytes()
                except OSError as error:
                    print(error, flush=True)
                    time.sleep(1)
                    continue
                if sent.get(script) == data:
                    continue
                snapshot = Path(temporary) / script.name
                snapshot.write_bytes(data)
                result = subprocess.run(
                    copy + ["--source", str(snapshot), "--destination", f"{destination}/{script.name}"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                )
                if result.returncode:
                    print(result.stdout, end="", flush=True)
                    time.sleep(1)
                else:
                    sent[script] = data
                    print(f"Sent {script.name} to iPhone", flush=True)
            time.sleep(0.25)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
