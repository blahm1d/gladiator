#!/usr/bin/env python3
"""Build a sprite-line oracle from a captured MAME hardware state.

The reference path deliberately follows MAME's documented graphics-layout
bit offsets and draw_sprites loop.  It does not call or translate the FPGA
renderer equations.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


PACK_SPRITE_P3 = 0x48000
PACK_SPRITE_P12 = 0x54000
SPRITE_P3_SIZE = 0x0C000
SPRITE_P12_SIZE = 0x18000


def read_capture(path: Path, requested_frame: int) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise SystemExit(f"no MAME sprite snapshots in {path}")
    exact = [row for row in rows if int(row["frame"]) == requested_frame]
    if exact:
        return exact[0]
    return min(rows, key=lambda row: abs(int(row["frame"]) - requested_frame))


def mame_sprite_region(pack: bytes) -> bytearray:
    region = bytearray(0x30000)
    region[0:SPRITE_P3_SIZE] = pack[
        PACK_SPRITE_P3 : PACK_SPRITE_P3 + SPRITE_P3_SIZE
    ]
    region[0x18000:0x30000] = pack[
        PACK_SPRITE_P12 : PACK_SPRITE_P12 + SPRITE_P12_SIZE
    ]

    # Exact init_gladiatr unpack loop from the pinned MAME driver.
    for block in range(5, -1, -1):
        source = bytes(region[block * 0x2000 : (block + 1) * 0x2000])
        region[(2 * block) * 0x2000 : (2 * block + 1) * 0x2000] = source
        region[
            (2 * block + 1) * 0x2000 : (2 * block + 2) * 0x2000
        ] = bytes(value >> 4 for value in source)

    def swap(first: int, second: int, length: int) -> None:
        left = bytes(region[first : first + length])
        right = bytes(region[second : second + length])
        region[first : first + length] = right
        region[second : second + length] = left

    swap(0x1A000, 0x1C000, 0x2000)
    swap(0x22000, 0x28000, 0x2000)
    swap(0x26000, 0x2C000, 0x2000)
    swap(0x24000, 0x28000, 0x4000)
    return region


def layout_pen(region: bytearray, tile: int, x: int, y: int) -> int:
    half_bits = 0x18000 * 8
    plane_offsets = (4, half_bits, half_bits + 4)
    x_offsets = (
        0,
        1,
        2,
        3,
        8 * 8 + 0,
        8 * 8 + 1,
        8 * 8 + 2,
        8 * 8 + 3,
        16 * 8 + 0,
        16 * 8 + 1,
        16 * 8 + 2,
        16 * 8 + 3,
        24 * 8 + 0,
        24 * 8 + 1,
        24 * 8 + 2,
        24 * 8 + 3,
    )
    y_offsets = (
        0 * 8,
        1 * 8,
        2 * 8,
        3 * 8,
        4 * 8,
        5 * 8,
        6 * 8,
        7 * 8,
        32 * 8,
        33 * 8,
        34 * 8,
        35 * 8,
        36 * 8,
        37 * 8,
        38 * 8,
        39 * 8,
    )
    base = tile * 64 * 8
    pen = 0
    for plane, plane_offset in enumerate(plane_offsets):
        bit_address = base + plane_offset + x_offsets[x] + y_offsets[y]
        value = region[bit_address >> 3]
        # MAME's gfx decoder maps planeoffset[0] to the MOST significant pen
        # bit: planebit = 1 << (planes - 1 - plane).  This oracle previously
        # used "<< plane", i.e. plane 0 as the LSB -- the reverse.  The RTL had
        # the identical inversion, so oracle and DUT agreed with each other and
        # 75,008 scanlines of "exact" agreement proved nothing about pen order.
        # The composite oracle, validated pixel-exact against MAME's own PNG
        # screenshots, is what exposed it.
        pen |= ((value >> (7 - (bit_address & 7))) & 1) << (len(plane_offsets) - 1 - plane)
    return pen


def draw_sprites(
    region: bytearray,
    ram: bytes,
    sprite_buffer: int,
    sprite_bank: int,
) -> list[list[int]]:
    image = [[0] * 256 for _ in range(256)]
    tile_offsets = ((0, 1), (2, 3))

    for offset in range(0, 0x80, 2):
        source = offset + (sprite_buffer << 7)
        attributes = ram[source + 0x800]
        size = (attributes >> 4) & 1
        bank = (attributes & 1) + (
            sprite_bank if (attributes & 2) else 0
        )
        tile_number = ram[source] + 256 * bank
        sx = ram[source + 0x401] + 256 * (ram[source + 0x801] & 1) - 0x38
        sy = 240 - ram[source + 0x400] - (16 if size else 0)
        xflip = bool(attributes & 0x04)
        yflip = bool(attributes & 0x08)
        color = ram[source + 1] & 0x1F

        for tile_y in range(size + 1):
            for tile_x in range(size + 1):
                source_tile_x = size - tile_x if xflip else tile_x
                source_tile_y = size - tile_y if yflip else tile_y
                tile = (
                    tile_number
                    + tile_offsets[source_tile_y][source_tile_x]
                )
                for local_y in range(16):
                    source_y = 15 - local_y if yflip else local_y
                    for local_x in range(16):
                        source_x = 15 - local_x if xflip else local_x
                        pen = layout_pen(region, tile, source_x, source_y)
                        if pen == 0:
                            continue
                        screen_x = sx + tile_x * 16 + local_x
                        if not 0 <= screen_x < 256:
                            continue
                        palette = 0x100 + color * 8 + pen
                        for screen_y in (
                            sy + tile_y * 16 + local_y,
                            sy + tile_y * 16 + local_y + 256,
                        ):
                            if 0 <= screen_y < 256:
                                image[screen_y][screen_x] = palette
    return image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    parser.add_argument("--frame", type=int, default=600)
    args = parser.parse_args()

    capture = read_capture(
        args.out / "mame-sprite-snapshots.csv", args.frame
    )
    ram = bytes.fromhex(capture["sprite_ram_hex"])
    if len(ram) != 0x0C00:
        raise SystemExit(f"captured {len(ram)} sprite bytes, expected 3072")

    pack = (args.out / "gladiatr.rom").read_bytes()
    if len(pack) < PACK_SPRITE_P12 + SPRITE_P12_SIZE:
        raise SystemExit("gladiatr.rom is shorter than the sprite regions")
    region = mame_sprite_region(pack)
    image = draw_sprites(
        region,
        ram,
        int(capture["sprite_buffer"]),
        int(capture["sprite_bank"]),
    )

    best_line = max(
        range(256),
        key=lambda line: sum(pixel != 0 for pixel in image[line]),
    )
    nonzero = sum(pixel != 0 for pixel in image[best_line])
    if nonzero == 0:
        raise SystemExit("selected MAME frame has no visible sprite pixels")

    (args.out / "mame-sprite-ram.hex").write_text(
        "".join(f"{value:02X}\n" for value in ram),
        encoding="ascii",
    )
    (args.out / "mame-sprite-line.hex").write_text(
        "".join(f"{value:03X}\n" for value in image[best_line]),
        encoding="ascii",
    )
    (args.out / "mame-sprite-oracle.txt").write_text(
        "\n".join(
            (
                f"frame={capture['frame']}",
                f"line={best_line}",
                f"sprite_buffer={capture['sprite_buffer']}",
                f"sprite_bank={capture['sprite_bank']}",
                f"nonzero_pixels={nonzero}",
                "",
            )
        ),
        encoding="ascii",
    )
    print(
        "PASS MAME sprite oracle: "
        f"frame {capture['frame']} line {best_line}, "
        f"{nonzero} non-transparent pixels"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
