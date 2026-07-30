#!/usr/bin/env python3
"""Audit gladiatr.zip and build the exact byte stream consumed by index 0.

The output is derived ROM data and must remain uncommitted.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
from pathlib import Path
import zipfile


PARTS = [
    ("qb0_5", 0x4000, 0x25B19EFB),
    ("qb0_4", 0x2000, 0x347EC794),
    ("qb0_1", 0x4000, 0x040C9839),
    ("qc0_3", 0x8000, 0x8D182326),
    ("qb0_17", 0x4000, 0xE78BE010),
    ("qb0_20", 0x8000, 0x15916EDA),
    ("qb0_19", 0x8000, 0x79CAA7ED),
    ("qb0_18", 0x8000, 0xE9591260),
    ("qc0_15", 0x2000, 0xA7EFA340),
    ("qb0_12", 0x8000, 0x0585D9AC),
    ("qb0_13", 0x8000, 0xA6BB797B),
    ("qb0_14", 0x8000, 0x85B71211),
    ("qc1_6", 0x4000, 0x651E6E44),
    ("qc2_7", 0x8000, 0xC992C4F7),
    ("qc0_8", 0x4000, 0x1C7FFDAD),
    ("qc1_9", 0x4000, 0x01043E03),
    ("qc1_10", 0x8000, 0x364CDB58),
    ("qc2_11", 0x8000, 0xC9FECFFF),
    ("q3.2b", 0x20, 0x6A7C3C60),
    ("q4.5s", 0x20, 0xE325808E),
    ("aq_002.9b", 0x400, 0xB30D225F),
    ("aq_003.xx", 0x400, 0x1D02CD5F),
    ("aq_006.3a", 0x400, 0x3C5CA4C6),
    ("aq_007.6c", 0x800, 0xF19AF04D),
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()

    stream = bytearray()
    manifest: dict[str, object] = {"source": str(args.zip), "parts": []}

    with zipfile.ZipFile(args.zip) as archive:
        root = {
            info.filename: info
            for info in archive.infolist()
            if "/" not in info.filename.rstrip("/")
        }

        for name, expected_size, expected_crc in PARTS:
            if name not in root:
                raise SystemExit(f"missing parent ROM: {name}")
            data = archive.read(name)
            crc = binascii.crc32(data) & 0xFFFFFFFF
            if len(data) != expected_size or crc != expected_crc:
                raise SystemExit(
                    f"{name}: size/crc {len(data):x}/{crc:08x}, "
                    f"expected {expected_size:x}/{expected_crc:08x}"
                )
            offset = len(stream)
            stream.extend(data)
            manifest["parts"].append(
                {
                    "name": name,
                    "offset": offset,
                    "size": len(data),
                    "crc32": f"{crc:08x}",
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
            )

    if len(stream) != 0x6D440:
        raise SystemExit(f"unexpected stream size: 0x{len(stream):x}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(stream)
    manifest["size"] = len(stream)
    manifest["sha256"] = hashlib.sha256(stream).hexdigest()

    manifest_path = args.manifest or args.output.with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {args.output} ({len(stream)} bytes)")
    print(f"sha256 {manifest['sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

