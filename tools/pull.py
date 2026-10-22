# Copies Slate's whole library (notebooks, ink, pictures, recordings, templates) from the
# iPad to the PC. Read-only on the iPad.
#   python tools/pull.py                      -> D:\ipad\slate-backup\<date-time>
#   python tools/pull.py "D:\somewhere"
import asyncio
import datetime
import os
import posixpath
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService

BUNDLE = "app.slate.notes.89MB4XXLYZ"


async def connect():
    for _ in range(40):
        try:
            lockdown = await create_using_usbmux()
            return await HouseArrestService.create(lockdown, BUNDLE, documents_only=True)
        except Exception as e:
            print("waiting for iPad:", type(e).__name__, flush=True)
            await asyncio.sleep(3)
    raise SystemExit("iPad not reachable.")


async def copy_tree(ha, remote, local):
    os.makedirs(local, exist_ok=True)
    count = 0
    for name in await ha.listdir(remote):
        if name in (".", ".."):
            continue
        r = posixpath.join(remote, name)
        l = os.path.join(local, name)
        info = await ha.stat(r)
        if info.get("st_ifmt") == "S_IFDIR":
            count += await copy_tree(ha, r, l)
        else:
            data = await ha.get_file_contents(r)
            with open(l, "wb") as f:
                f.write(data)
            count += 1
    return count


async def main():
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(r"D:\ipad\slate-backup", stamp)
    ha = await connect()
    total = 0
    for folder in ("Library", "Templates"):
        try:
            total += await copy_tree(ha, "/Documents/" + folder, os.path.join(target, folder))
        except Exception as e:
            print("skipped", folder, type(e).__name__)
    print(f"{total} files copied to {target}")


asyncio.run(main())
