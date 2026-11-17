"""Puts a Nami IPA in LiveContainer's Documents folder on an iPhone plugged in over USB.

    uvx --from pymobiledevice3 python -I tools/push-ipa.py app/xtool/Nami.ipa [name.ipa] [bundle id]

xtool stores the IPA uncompressed (about 60 MB); it is recompressed first (about
20 MB, same content, checked), which is also small enough to send another way
when the phone is not plugged in: the copy is written next to the original.
LiveContainer's app ID changes each time it is reinstalled; pass the new one.
"""

import hashlib
import sys
import zipfile
from pathlib import Path

source = Path(sys.argv[1])
name = sys.argv[2] if len(sys.argv) > 2 else 'Nami.ipa'
bundle = sys.argv[3] if len(sys.argv) > 3 else 'com.kdt.livecontainer.8VFKPL4NLN'

small = source.with_name(name if name != source.name else f'{source.stem}-small.ipa')
with zipfile.ZipFile(source) as src, zipfile.ZipFile(small, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as out:
    for item in src.infolist():
        out.writestr(item, src.read(item.filename), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
with zipfile.ZipFile(source) as src, zipfile.ZipFile(small) as new:
    assert new.testzip() is None
    for item in src.infolist():
        assert hashlib.sha256(src.read(item)).digest() == hashlib.sha256(new.read(item.filename)).digest()
print(f'{small} ({small.stat().st_size / 1e6:.1f} MB, same content)')

import asyncio  # noqa: E402
import inspect  # noqa: E402

from pymobiledevice3.lockdown import create_using_usbmux  # noqa: E402
from pymobiledevice3.services.house_arrest import HouseArrestService  # noqa: E402


async def done(value):
    """pymobiledevice3 moved to async calls; older versions answer at once."""
    return await value if inspect.isawaitable(value) else value


async def push():
    lockdown = await done(create_using_usbmux())
    afc = await done(HouseArrestService.create(lockdown, bundle, documents_only=True))
    await done(afc.set_file_contents(f'/Documents/{name}', small.read_bytes()))
    print(await done(afc.listdir('/Documents')))


asyncio.run(push())
