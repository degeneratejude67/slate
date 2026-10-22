# Copies lecture PDFs from the PC into Slate's library on the iPad (over USB or Wi-Fi sync).
# Slate turns every PDF it finds in its library into a notebook the next time it opens,
# in the same folder, so this only has to drop PDFs in the right place.
#
#   python tools/push.py "D:\4-1study\ME 445\slides" "4-1 Study/ME 445"
#   python tools/push.py lecture.pdf "4-1 Study/ME 421/Ali"
#
# Folders under the local folder are mirrored. A PDF is skipped when the target folder
# already has a notebook or PDF of the same name, so running it twice adds nothing.
import argparse
import asyncio
import os
import posixpath
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService

BUNDLE = "app.slate.notes.89MB4XXLYZ"


async def connect(bundle):
    for attempt in range(40):
        try:
            lockdown = await create_using_usbmux()
            return await HouseArrestService.create(lockdown, bundle, documents_only=True)
        except Exception as e:  # the Lightning link drops now and then
            print("waiting for iPad:", type(e).__name__, flush=True)
            await asyncio.sleep(3)
    raise SystemExit("iPad not reachable. Plug it in, unlock it, and open Slate once.")


async def exists(ha, path):
    try:
        await ha.stat(path)
        return True
    except Exception:
        return False


async def mkdirs(ha, path):
    current = ""
    for part in [p for p in path.split("/") if p]:
        current += "/" + part
        if not await exists(ha, current):
            await ha.makedirs(current)


def local_pdfs(source):
    if os.path.isfile(source):
        return [(source, "")]
    found = []
    for folder, _, files in os.walk(source):
        rel = os.path.relpath(folder, source).replace("\\", "/")
        for name in sorted(files):
            if name.lower().endswith(".pdf"):
                found.append((os.path.join(folder, name), "" if rel == "." else rel))
    return found


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", help="a PDF or a folder of PDFs on the PC")
    parser.add_argument("target", help='folder inside Slate\'s library, e.g. "4-1 Study/ME 445"')
    parser.add_argument("--app", default=BUNDLE, help="Slate's bundle id on the iPad")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    ha = await connect(args.app)
    base = posixpath.join("/Documents/Library", args.target.strip("/"))
    added = skipped = 0
    for path, rel in local_pdfs(args.source):
        folder = posixpath.join(base, rel) if rel else base
        stem = os.path.splitext(os.path.basename(path))[0]
        if await exists(ha, posixpath.join(folder, stem + ".slate")) or await exists(ha, posixpath.join(folder, stem + ".pdf")):
            print("skip  ", posixpath.join(folder, stem))
            skipped += 1
            continue
        print("add   ", posixpath.join(folder, stem + ".pdf"))
        if args.dry_run:
            continue
        await mkdirs(ha, folder)
        data = open(path, "rb").read()
        partial = posixpath.join(folder, "." + stem + ".partial")
        await ha.set_file_contents(partial, data)
        if int((await ha.stat(partial))["st_size"]) != len(data):
            raise SystemExit("size mismatch on " + partial)
        await ha.rename(partial, posixpath.join(folder, stem + ".pdf"))   # appears whole, never half-copied
        added += 1
    print(f"{added} added, {skipped} already there. Open Slate to turn them into notebooks.")


asyncio.run(main())
