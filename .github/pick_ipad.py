# Reads `xcrun simctl list devices available -j` on stdin and prints the UDID of an iPad
# simulator on the newest iOS runtime, preferring the plain iPad (closest to an iPad 9th gen).
import json
import re
import sys

devices = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in re.findall(r"\d+", runtime.split("iOS")[-1]))
    for dev in devs:
        name = dev["name"]
        if not name.startswith("iPad") or not dev.get("isAvailable", True):
            continue
        plain = 2 if re.match(r"iPad \(", name) else (1 if "Air" in name else 0)
        score = (version, plain)
        if best is None or score > best[0]:
            best = (score, dev["udid"], name, runtime)

if best is None:
    sys.exit("no iPad simulator found")
sys.stderr.write(f"Using {best[2]} on {best[3]}\n")
print(best[1])
