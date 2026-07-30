#!/usr/bin/env python3
"""Build a full-frame sprite oracle from captured MAME hardware states.

The single-line oracle in build_sprite_oracle.py compares 256 pixels of one
scanline of one frame.  That is not coverage.  This script emits every one of
the 256 sprite-plane scanlines for every captured frame so the RTL renderer is
diffed over whole images across the full range of descriptor states MAME
actually produced.

The reference path is the same independent transcription of MAME's documented
graphics-layout bit offsets and draw_sprites loop used by the line oracle.  It
does not call or translate the FPGA renderer equations.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from build_sprite_oracle import draw_sprites, mame_sprite_region

PACK_SPRITE_P12 = 0x54000
SPRITE_P12_SIZE = 0x18000


def read_captures(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise SystemExit(f"no MAME sprite snapshots in {path}")
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    parser.add_argument(
        "--frames",
        type=int,
        default=0,
        help="limit to the first N frames that contain sprite pixels",
    )
    parser.add_argument(
        "--force-buffer",
        type=int,
        default=-1,
        help="override the captured sprite_buffer bit (coverage probe)",
    )
    parser.add_argument(
        "--snapshots",
        type=Path,
        default=None,
        help="MAME sprite snapshot CSV (default <out>/mame-sprite-snapshots.csv)",
    )
    parser.add_argument(
        "--frame-dir",
        type=Path,
        default=None,
        help="oracle output directory (default <out>/sprite-frames)",
    )
    args = parser.parse_args()

    pack = (args.out / "gladiatr.rom").read_bytes()
    if len(pack) < PACK_SPRITE_P12 + SPRITE_P12_SIZE:
        raise SystemExit("gladiatr.rom is shorter than the sprite regions")
    region = mame_sprite_region(pack)

    snapshots = args.snapshots or (args.out / "mame-sprite-snapshots.csv")
    frame_dir = args.frame_dir or (args.out / "sprite-frames")
    frame_dir.mkdir(parents=True, exist_ok=True)

    buffer_mix = {0: 0, 1: 0}
    emitted: list[tuple[int, int, int, int]] = []
    for capture in read_captures(snapshots):
        ram = bytes.fromhex(capture["sprite_ram_hex"])
        if len(ram) != 0x0C00:
            raise SystemExit(
                f"captured {len(ram)} sprite bytes, expected 3072"
            )
        frame = int(capture["frame"])
        buffer_index = int(capture["sprite_buffer"])
        if args.force_buffer >= 0:
            buffer_index = args.force_buffer
        bank = int(capture["sprite_bank"])

        image = draw_sprites(region, ram, buffer_index, bank)
        nonzero = sum(
            1 for row in image for pixel in row if pixel != 0
        )
        # A frame with no visible sprite pixels cannot discriminate anything.
        # Skipping it is not weakening the oracle; an all-transparent image
        # passes trivially for any renderer.
        if nonzero == 0:
            continue

        (frame_dir / f"frame-{frame}-ram.hex").write_text(
            "".join(f"{value:02X}\n" for value in ram),
            encoding="ascii",
        )
        (frame_dir / f"frame-{frame}-image.hex").write_text(
            "".join(
                f"{pixel:03X}\n" for row in image for pixel in row
            ),
            encoding="ascii",
        )
        emitted.append((frame, buffer_index, bank, nonzero))
        buffer_mix[buffer_index] = buffer_mix.get(buffer_index, 0) + 1
        if args.frames and len(emitted) >= args.frames:
            break

    if not emitted:
        raise SystemExit("no captured frame contains visible sprite pixels")

    lines = [f"{len(emitted)}"]
    lines.extend(
        f"{frame} {buffer_index} {bank} {nonzero}"
        for frame, buffer_index, bank, nonzero in emitted
    )
    (frame_dir / "index.txt").write_text(
        "\n".join(lines) + "\n", encoding="ascii"
    )

    total = sum(entry[3] for entry in emitted)
    print(
        f"MIX sprite_buffer emitted frames: "
        f"buffer0={buffer_mix.get(0, 0)} buffer1={buffer_mix.get(1, 0)}"
    )
    print(
        f"PASS MAME sprite frame oracle: {len(emitted)} frames, "
        f"{len(emitted) * 256} scanlines, {total} non-transparent pixels"
    )
    for frame, buffer_index, bank, nonzero in emitted:
        print(
            f"  frame {frame}: buffer={buffer_index} bank={bank} "
            f"pixels={nonzero}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
