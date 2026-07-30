#!/usr/bin/env python3
"""Build a full COMPOSITE-frame oracle from captured MAME hardware states.

Every sprite gate in this tree compares the sprite plane in isolation.  The
composited image -- background tilemap, sprite plane, text/fg overlay, palette
lookup and layer priority -- has never been diffed against MAME.  The cabinet
symptom ("sprites look corrupt on screen") is produced just as readily by a
palette, priority or tile-plane defect as by the sprite builder.

This module is an INDEPENDENT transcription of the pinned MAME gospel:

  .codex-tmp/gladiatr-v-mame-master.cpp  (tilemap callbacks, draw_sprites,
                                          screen_update_gladiatr)
  .codex-tmp/gladiatr-mame-master.cpp    (gfx layouts, GFXDECODE colour bases,
                                          palette format, init_gladiatr unpack)

It deliberately does NOT read or translate rtl/video/gladiator_video.sv or
rtl/video/gladiator_sprite_line.sv.  Cross-checking the result against MAME's
own screenshots (sim/out/mame-full-snap/frame-XXXXX.png) closes the loop: the
oracle is validated against ground truth before the RTL is ever compared to it.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Pack layout.  Offsets follow scripts/build_rom.py PARTS in order.
# ---------------------------------------------------------------------------
PACK_TEXT = 0x2E000
TEXT_SIZE = 0x02000
PACK_BG_P3 = 0x30000
BG_P3_SIZE = 0x08000
PACK_BG_P12 = 0x38000
BG_P12_SIZE = 0x10000
PACK_SPRITE_P3 = 0x48000
SPRITE_P3_SIZE = 0x0C000
PACK_SPRITE_P12 = 0x54000
SPRITE_P12_SIZE = 0x18000

# gladiatr_cpu1_map: the snapshot CSV covers 0xd000..0xf7ff.
STATE_BASE = 0xD000
PALETTE_LO_OFF = 0xD000 - STATE_BASE
PALETTE_EX_OFF = 0xD400 - STATE_BASE
VIDEORAM_OFF = 0xD800 - STATE_BASE
COLORRAM_OFF = 0xE000 - STATE_BASE
TEXTRAM_OFF = 0xE800 - STATE_BASE

# screen.set_visarea(0*8, 32*8-1, 2*8, 30*8-1)
VIS_X0, VIS_X1 = 0, 255
VIS_Y0, VIS_Y1 = 16, 239


# ---------------------------------------------------------------------------
# init_gladiatr() graphics unpack -- transcribed from the gospel.
# ---------------------------------------------------------------------------
def _unpack_3bpp(region: bytearray, blocks: int) -> None:
    """for (int j = blocks-1; j >= 0; j--) { rom[i+(2j+1)*0x2000] = rom[i+j*0x2000] >> 4;
    rom[i+2j*0x2000] = rom[i+j*0x2000]; }"""
    for j in range(blocks - 1, -1, -1):
        source = bytes(region[j * 0x2000 : (j + 1) * 0x2000])
        region[(2 * j + 1) * 0x2000 : (2 * j + 2) * 0x2000] = bytes(
            value >> 4 for value in source
        )
        region[(2 * j) * 0x2000 : (2 * j + 1) * 0x2000] = source


def _swap_ranges(region: bytearray, first: int, last: int, second: int) -> None:
    """std::swap_ranges(rom+first, rom+last, rom+second)"""
    length = last - first
    left = bytes(region[first:last])
    right = bytes(region[second : second + length])
    region[first:last] = right
    region[second : second + length] = left


def mame_bg_region(pack: bytes) -> bytearray:
    region = bytearray(0x20000)
    region[0x00000 : 0x00000 + BG_P3_SIZE] = pack[
        PACK_BG_P3 : PACK_BG_P3 + BG_P3_SIZE
    ]
    region[0x10000 : 0x10000 + BG_P12_SIZE] = pack[
        PACK_BG_P12 : PACK_BG_P12 + BG_P12_SIZE
    ]
    _unpack_3bpp(region, 4)
    _swap_ranges(region, 0x14000, 0x18000, 0x18000)
    return region


def mame_sprite_region(pack: bytes) -> bytearray:
    region = bytearray(0x30000)
    region[0x00000 : 0x00000 + SPRITE_P3_SIZE] = pack[
        PACK_SPRITE_P3 : PACK_SPRITE_P3 + SPRITE_P3_SIZE
    ]
    region[0x18000 : 0x18000 + SPRITE_P12_SIZE] = pack[
        PACK_SPRITE_P12 : PACK_SPRITE_P12 + SPRITE_P12_SIZE
    ]
    _unpack_3bpp(region, 6)
    _swap_ranges(region, 0x1A000, 0x1C000, 0x1C000)
    _swap_ranges(region, 0x22000, 0x24000, 0x28000)
    _swap_ranges(region, 0x26000, 0x28000, 0x2C000)
    _swap_ranges(region, 0x24000, 0x28000, 0x28000)
    return region


def mame_text_region(pack: bytes) -> bytes:
    return pack[PACK_TEXT : PACK_TEXT + TEXT_SIZE]


# ---------------------------------------------------------------------------
# gfx_layout decode.
#
# gfx_element::decode() assigns the FIRST planeoffset in the list to the MOST
# significant pen bit:  planebit = 1 << (planes - 1 - plane).  The driver ROM
# comments agree -- qb0_12 / qc1_6+qc2_7 (region first half, planeoffset 4) are
# labelled "plane 3", the second-half ROMs "planes 1,2".
# ---------------------------------------------------------------------------
def make_pen_tables(
    region_bytes: int,
    width: int,
    height: int,
    x_offsets: tuple[int, ...],
    y_offsets: tuple[int, ...],
    char_increment: int,
    plane_swap_20: bool = False,
) -> tuple[tuple[int, ...], int, int, int]:
    half_bits = (region_bytes // 2) * 8
    plane_offsets = (4, half_bits, half_bits + 4)
    planes = len(plane_offsets)
    table = []
    for y in range(height):
        for x in range(width):
            entry = []
            for plane, plane_offset in enumerate(plane_offsets):
                bit_address = plane_offset + x_offsets[x] + y_offsets[y]
                pen_bit = planes - 1 - plane
                if plane_swap_20 and pen_bit != 1:
                    pen_bit = 2 - pen_bit
                entry.append((bit_address, pen_bit))
            table.append(tuple(entry))
    return tuple(table), width, height, char_increment


TILE_X_OFFSETS = (0, 1, 2, 3, 8 * 8 + 0, 8 * 8 + 1, 8 * 8 + 2, 8 * 8 + 3)
TILE_Y_OFFSETS = tuple(i * 8 for i in range(8))
SPRITE_X_OFFSETS = (
    0, 1, 2, 3,
    8 * 8 + 0, 8 * 8 + 1, 8 * 8 + 2, 8 * 8 + 3,
    16 * 8 + 0, 16 * 8 + 1, 16 * 8 + 2, 16 * 8 + 3,
    24 * 8 + 0, 24 * 8 + 1, 24 * 8 + 2, 24 * 8 + 3,
)
SPRITE_Y_OFFSETS = tuple(i * 8 for i in range(8)) + tuple(
    (32 + i) * 8 for i in range(8)
)


def decode_tile(region, table, char_increment, tile, cache):
    """Return a flat list of pens for one decoded character."""
    pens = cache.get(tile)
    if pens is not None:
        return pens
    base = tile * char_increment
    entry_table, width, height, _ = table
    pens = []
    for entry in entry_table:
        pen = 0
        for bit_address, pen_bit in entry:
            address = base + bit_address
            byte = region[address >> 3]
            pen |= ((byte >> (7 - (address & 7))) & 1) << pen_bit
        pens.append(pen)
    cache[tile] = pens
    return pens


# ---------------------------------------------------------------------------
# Video-register reconstruction from the event trace.
# ---------------------------------------------------------------------------
REGISTER_ADDRESSES = {
    0xCC00: "fg_scrolly",
    0xCC80: "video_attributes",
    0xCD00: "fg_scrollx",
    0xCE00: "bg_scrolly",
    0xCF00: "bg_scrollx",
}


def reconstruct_registers(events_path: Path, cache_path: Path) -> dict:
    """Replay every gladiatr_video_registers_w / mainlatch write.

    The trace tags a write with the frame number that was current when the tap
    fired.  register_frame_done() updates that tag *before* the snapshot rows
    are emitted, so a write seen during frame F carries the tag F-1 and the
    state belonging to the snapshot of frame F is "all writes tagged <= F-1".
    """
    if cache_path.exists():
        cached = json.loads(cache_path.read_text(encoding="ascii"))
        if cached.get("source_size") == events_path.stat().st_size:
            return {int(k): v for k, v in cached["frames"].items()}

    state = {
        "fg_scrolly": 0,
        "fg_scrollx": 0,
        "bg_scrolly": 0,
        "bg_scrollx": 0,
        "video_attributes": 0,
        "sprite_buffer": 0,
        "sprite_bank": 2,
        "flip_screen": 0,
    }
    frames: dict[int, dict] = {0: dict(state)}
    current_tag = 0
    stray = 0

    with events_path.open("r", encoding="ascii", newline="") as stream:
        stream.readline()
        for line in stream:
            # tick,frame,domain,kind,address,data,pc,count,last
            if ",write," not in line:
                continue
            parts = line.split(",")
            domain = parts[2]
            if domain != "main_mem" and domain != "main_io":
                continue
            address = int(parts[4], 16)
            if domain == "main_mem":
                if address < 0xCC00 or address > 0xCFFF:
                    continue
            else:
                if address > 0xC007:
                    continue
            tag = int(parts[1])
            if tag > current_tag:
                for frame in range(current_tag + 1, tag + 1):
                    frames[frame] = dict(state)
                current_tag = tag
            data = int(parts[5], 16)
            if domain == "main_mem":
                name = REGISTER_ADDRESSES.get(address)
                if name is None:
                    stray += 1
                    continue
                state[name] = data
            else:
                bit = address & 7
                value = data & 1
                if bit == 0:
                    state["sprite_buffer"] = value
                elif bit == 1:
                    state["sprite_bank"] = 4 if value else 2
                elif bit == 7:
                    state["flip_screen"] = value

    for frame in range(current_tag + 1, current_tag + 4):
        frames[frame] = dict(state)

    if stray:
        raise SystemExit(
            f"{stray} writes inside 0xcc00-0xcfff hit no video register offset"
        )

    cache_path.write_text(
        json.dumps(
            {
                "source_size": events_path.stat().st_size,
                "frames": {str(k): v for k, v in frames.items()},
            }
        ),
        encoding="ascii",
    )
    return frames


# ---------------------------------------------------------------------------
# screen_update_gladiatr()
# ---------------------------------------------------------------------------
def render_composite(
    state: dict,
    regs: dict,
    bg_region: bytearray,
    sprite_region: bytearray,
    text_region: bytes,
    bg_table,
    sprite_table,
    mutate_priority: bool = False,
    mutate_bg_attr_skew: bool = False,
) -> list[list[int]]:
    """Return a 256x256 bitmap of palette indices (cliprect rows only)."""
    bitmap = [[0] * 256 for _ in range(256)]

    video_attributes = regs["video_attributes"]
    if not (video_attributes & 0x20):
        # bitmap.fill(m_palette->black_pen(), cliprect)
        return bitmap

    if regs["flip_screen"]:
        raise SystemExit("flip_screen frames are outside this oracle's scope")

    videoram = state["videoram"]
    colorram = state["colorram"]
    textram = state["textram"]
    spriteram = state["spriteram"]

    bg_scroll = regs["bg_scrollx"] + ((video_attributes & 0x04) << 6)
    fg_scroll = regs["fg_scrollx"] + ((video_attributes & 0x08) << 5)
    bg_tile_bank = (video_attributes & 0x10) >> 4
    fg_tile_bank = video_attributes & 0x03

    # tilemap_t::effective_rowscroll() = m_dx - rowscroll, and draw_instance()
    # places the tilemap origin there, so source = screen - effective.
    bg_dx = (0x30 + bg_scroll) % 512
    fg_dx = (0x30 + fg_scroll) % 512
    bg_dy = regs["bg_scrolly"] % 256
    fg_dy = regs["fg_scrolly"] % 256

    bg_cache: dict[int, list[int]] = {}
    sprite_cache: dict[int, list[int]] = {}

    # --- background tilemap (opaque) ---------------------------------------
    for y in range(VIS_Y0, VIS_Y1 + 1):
        source_y = (y + bg_dy) & 0xFF
        row = bitmap[y]
        tile_row = (source_y >> 3) * 64
        fine_y = source_y & 7
        for x in range(256):
            source_x = (x + bg_dx) & 0x1FF
            tile_index = tile_row + (source_x >> 3)
            attr = colorram[tile_index]
            code = (
                videoram[tile_index]
                + ((attr & 0x07) << 8)
                + (bg_tile_bank << 11)
            )
            if mutate_bg_attr_skew:
                attr = colorram[
                    tile_row + (((x + 1 + bg_dx) & 0x1FF) >> 3)
                ]
            pens = decode_tile(bg_region, bg_table, 16 * 8, code, bg_cache)
            pen = pens[fine_y * 8 + (source_x & 7)]
            row[x] = 0x000 + ((attr >> 3) ^ 0x1F) * 8 + pen

    # --- sprites (transparent pen 0) ---------------------------------------
    tile_offset = ((0, 1), (2, 3))
    sprite_buffer = regs["sprite_buffer"]
    sprite_bank = regs["sprite_bank"]

    def draw_sprites() -> None:
        for offs in range(0, 0x80, 2):
            src = offs + (sprite_buffer << 7)
            attributes = spriteram[src + 0x800]
            size = (attributes >> 4) & 1
            bank = (attributes & 1) + (sprite_bank if (attributes & 2) else 0)
            tile_number = spriteram[src] + 256 * bank
            sx = (
                spriteram[src + 0x401]
                + 256 * (spriteram[src + 0x801] & 1)
                - 0x38
            )
            sy = 240 - spriteram[src + 0x400] - (16 if size else 0)
            xflip = bool(attributes & 0x04)
            yflip = bool(attributes & 0x08)
            color = spriteram[src + 1] & 0x1F
            palette_base = 0x100 + color * 8

            for y in range(size + 1):
                for x in range(size + 1):
                    ex = (size - x) if xflip else x
                    ey = (size - y) if yflip else y
                    tile = tile_offset[ey][ex] + tile_number
                    pens = decode_tile(
                        sprite_region, sprite_table, 64 * 8, tile, sprite_cache
                    )
                    for local_y in range(16):
                        read_y = (15 - local_y) if yflip else local_y
                        base_y = sy + y * 16 + local_y
                        for wrap in (0, 256):
                            screen_y = base_y + wrap
                            if not VIS_Y0 <= screen_y <= VIS_Y1:
                                continue
                            row = bitmap[screen_y]
                            for local_x in range(16):
                                screen_x = sx + x * 16 + local_x
                                if not 0 <= screen_x < 256:
                                    continue
                                read_x = (15 - local_x) if xflip else local_x
                                pen = pens[read_y * 16 + read_x]
                                if pen == 0:
                                    continue
                                row[screen_x] = palette_base + pen

    # --- fg/text tilemap (transparent pen 0, colour base 0x200) ------------
    def draw_fg() -> None:
        for y in range(VIS_Y0, VIS_Y1 + 1):
            source_y = (y + fg_dy) & 0xFF
            row = bitmap[y]
            tile_row = (source_y >> 3) * 64
            fine_y = source_y & 7
            for x in range(256):
                source_x = (x + fg_dx) & 0x1FF
                code = textram[tile_row + (source_x >> 3)] + (fg_tile_bank << 8)
                byte = text_region[code * 8 + fine_y]
                if (byte >> (7 - (source_x & 7))) & 1:
                    row[x] = 0x201

    # screen_update_gladiatr(): bg, then draw_sprites(), then the fg tilemap.
    if mutate_priority:
        draw_fg()
        draw_sprites()
    else:
        draw_sprites()
        draw_fg()

    return bitmap


def palette_rgb(state: dict, index: int) -> tuple[int, int, int, int]:
    """palette_device::xBGRBBBBGGGGRRRR_bit0 -> (rgb555, r8, g8, b8)."""
    data = state["palette_lo"][index] | (state["palette_ex"][index] << 8)
    red = ((data & 0x0F) << 1) | ((data >> 12) & 1)
    green = (((data >> 4) & 0x0F) << 1) | ((data >> 13) & 1)
    blue = (((data >> 8) & 0x0F) << 1) | ((data >> 14) & 1)
    rgb555 = (red << 10) | (green << 5) | blue

    def pal5bit(value: int) -> int:
        return ((value << 3) | (value >> 2)) & 0xFF

    return rgb555, pal5bit(red), pal5bit(green), pal5bit(blue)


# ---------------------------------------------------------------------------
def load_states(out: Path) -> dict[int, dict]:
    states: dict[int, dict] = {}
    with (out / "mame-state-snapshots.csv").open(
        newline="", encoding="utf-8"
    ) as stream:
        for row in csv.DictReader(stream):
            raw = bytes.fromhex(row["main_ram_d000_f7ff_hex"])
            if len(raw) != 0x2800:
                raise SystemExit("state snapshot is not 0x2800 bytes")
            states[int(row["frame"])] = {
                "palette_lo": raw[PALETTE_LO_OFF : PALETTE_LO_OFF + 0x400],
                "palette_ex": raw[PALETTE_EX_OFF : PALETTE_EX_OFF + 0x400],
                "videoram": raw[VIDEORAM_OFF : VIDEORAM_OFF + 0x800],
                "colorram": raw[COLORRAM_OFF : COLORRAM_OFF + 0x800],
                "textram": raw[TEXTRAM_OFF : TEXTRAM_OFF + 0x800],
            }
    return states


def load_sprite_states(out: Path) -> dict[int, dict]:
    sprites: dict[int, dict] = {}
    with (out / "mame-sprite-snapshots.csv").open(
        newline="", encoding="utf-8"
    ) as stream:
        for row in csv.DictReader(stream):
            ram = bytes.fromhex(row["sprite_ram_hex"])
            if len(ram) != 0x0C00:
                raise SystemExit("sprite snapshot is not 0x0c00 bytes")
            sprites[int(row["frame"])] = {
                "spriteram": ram,
                "sprite_buffer": int(row["sprite_buffer"]),
                "sprite_bank": int(row["sprite_bank"]),
                "video_attributes": int(row["video_attributes"], 16),
            }
    return sprites


def write_hex(path: Path, values, width: int) -> None:
    path.write_text(
        "".join(f"{value:0{width}X}\n" for value in values), encoding="ascii"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    parser.add_argument(
        "--frames",
        type=str,
        default="",
        help="comma separated capture frames (default: auto-select)",
    )
    # Default was 4 while 49 MAME screenshots sat unused in sim/out/mame-full-snap.
    # The gate that found the pen-order and attribute-skew bugs was running at 8%
    # of available ground truth. Cover every frame that has BOTH a screenshot and
    # a state snapshot; --count still narrows it for quick iteration.
    parser.add_argument("--count", type=int, default=60)
    # Default was 250, which excluded the boot/self-test/attract frames entirely.
    # The gate is meant to cover everything with ground truth, not a window
    # someone chose once. (The title screen is still absent -- MAME's capture
    # had a coin inserted early and never showed it. That is a CAPTURE gap, not
    # a range gap, and needs a no-coin attract run to close.)
    parser.add_argument("--min-frame", type=int, default=0)
    parser.add_argument(
        "--dir", type=str, default="composite-frames",
        help="output subdirectory under --out",
    )
    parser.add_argument(
        "--mutate-plane-order",
        action="store_true",
        help="coverage probe: assign gfx planeoffset[0] to pen bit 0 instead "
             "of the MAME MSB (the misreading under test)",
    )
    parser.add_argument(
        "--mutate-priority",
        action="store_true",
        help="coverage probe: draw the fg overlay before the sprites",
    )
    parser.add_argument(
        "--mutate-bg-attr-skew",
        action="store_true",
        help="coverage probe: take the background colour attribute from the "
             "tile one screen pixel to the right",
    )
    parser.add_argument(
        "--skip-png", action="store_true",
        help="skip the MAME screenshot cross-check",
    )
    args = parser.parse_args()

    out: Path = args.out
    pack = (out / "gladiatr.rom").read_bytes()
    if len(pack) != 0x6D440:
        raise SystemExit(f"unexpected pack size 0x{len(pack):x}")

    bg_region = mame_bg_region(pack)
    sprite_region = mame_sprite_region(pack)
    text_region = mame_text_region(pack)
    bg_table = make_pen_tables(
        0x20000, 8, 8, TILE_X_OFFSETS, TILE_Y_OFFSETS, 16 * 8,
        args.mutate_plane_order,
    )
    sprite_table = make_pen_tables(
        0x30000, 16, 16, SPRITE_X_OFFSETS, SPRITE_Y_OFFSETS, 64 * 8,
        args.mutate_plane_order,
    )

    states = load_states(out)
    sprite_states = load_sprite_states(out)
    registers = reconstruct_registers(
        out / "mame-full-events.csv", out / "composite-video-registers.json"
    )

    # The reconstruction is validated against the three register fields the
    # capture recorded independently in its own snapshot rows.
    checked = 0
    for frame, sprite_state in sorted(sprite_states.items()):
        # The event trace stops at GLADIATR_TRACE_UNTIL_FRAME; state snapshots
        # continue past it.  Frames with no trace coverage cannot be replayed
        # and are excluded from selection below, not silently defaulted.
        regs = registers.get(frame)
        if regs is None:
            continue
        for name in ("video_attributes", "sprite_buffer", "sprite_bank"):
            if regs[name] != sprite_state[name]:
                raise SystemExit(
                    f"register replay disagrees with the capture at frame "
                    f"{frame}: {name} replay={regs[name]:#x} "
                    f"capture={sprite_state[name]:#x}"
                )
        checked += 1
    print(
        f"register replay cross-check: {checked} snapshots agree on "
        "video_attributes, sprite_buffer and sprite_bank"
    )

    if args.frames:
        selected = [int(value) for value in args.frames.split(",")]
    else:
        selected = []
        for frame in sorted(states):
            if frame < args.min_frame or frame not in registers:
                continue
            regs = registers[frame]
            if not (regs["video_attributes"] & 0x20) or regs["flip_screen"]:
                continue
            if frame not in sprite_states:
                continue
            if not any(sprite_states[frame]["spriteram"]):
                continue
            if not args.skip_png:
                if not (
                    out / "mame-full-snap" / f"frame-{frame:05d}.png"
                ).exists():
                    continue
            selected.append(frame)
            if len(selected) >= args.count:
                break
    if not selected:
        raise SystemExit("no capture frame satisfies the selection")

    frame_dir = out / args.dir
    frame_dir.mkdir(parents=True, exist_ok=True)

    index_lines = [str(len(selected))]
    png_failures = 0
    png_checked = 0
    for frame in selected:
        state = dict(states[frame])
        sprite_state = sprite_states[frame]
        state["spriteram"] = sprite_state["spriteram"]
        regs = registers[frame]

        bitmap = render_composite(
            state, regs, bg_region, sprite_region, text_region,
            bg_table, sprite_table, args.mutate_priority,
            args.mutate_bg_attr_skew,
        )

        indices = []
        rgb555 = []
        for y in range(VIS_Y0, VIS_Y1 + 1):
            for x in range(256):
                index = bitmap[y][x]
                indices.append(index)
                rgb555.append(palette_rgb(state, index)[0])

        write_hex(frame_dir / f"frame-{frame}-idx.hex", indices, 3)
        write_hex(frame_dir / f"frame-{frame}-rgb.hex", rgb555, 4)
        write_hex(frame_dir / f"frame-{frame}-pallo.hex", state["palette_lo"], 2)
        write_hex(frame_dir / f"frame-{frame}-palex.hex", state["palette_ex"], 2)
        write_hex(frame_dir / f"frame-{frame}-bgcode.hex", state["videoram"], 2)
        write_hex(frame_dir / f"frame-{frame}-bgattr.hex", state["colorram"], 2)
        write_hex(frame_dir / f"frame-{frame}-fgcode.hex", state["textram"], 2)
        write_hex(
            frame_dir / f"frame-{frame}-sprite.hex", state["spriteram"], 2
        )

        distinct = len(set(indices))
        sprite_pixels = sum(1 for value in indices if 0x100 <= value < 0x200)
        fg_pixels = sum(1 for value in indices if value >= 0x200)
        bg_pens = len({value & 7 for value in indices if value < 0x100})
        coverage = (
            f"sprite={sprite_pixels} fg={fg_pixels} "
            f"bg_pens={bg_pens} indices={distinct}"
        )
        index_lines.append(
            " ".join(
                str(value)
                for value in (
                    frame,
                    regs["video_attributes"],
                    regs["fg_scrollx"],
                    regs["fg_scrolly"],
                    regs["bg_scrollx"],
                    regs["bg_scrolly"],
                    regs["flip_screen"],
                    regs["sprite_buffer"],
                    regs["sprite_bank"],
                    distinct,
                )
            )
        )

        png_path = out / "mame-full-snap" / f"frame-{frame:05d}.png"
        if args.skip_png or not png_path.exists():
            print(f"  frame {frame}: {coverage}")
            continue

        from PIL import Image

        with Image.open(png_path) as image:
            reference = image.convert("RGB")
            if reference.size != (256, 224):
                raise SystemExit(f"{png_path} is {reference.size}, expected 256x224")
            pixels = reference.load()
        bad = 0
        first_bad = None
        for y in range(VIS_Y0, VIS_Y1 + 1):
            for x in range(256):
                _, r8, g8, b8 = palette_rgb(state, bitmap[y][x])
                if pixels[x, y - VIS_Y0] != (r8, g8, b8):
                    if first_bad is None:
                        first_bad = (
                            x, y, (r8, g8, b8), pixels[x, y - VIS_Y0],
                            bitmap[y][x],
                        )
                    bad += 1
        png_checked += 1
        if bad:
            png_failures += 1
            x, y, mine, theirs, index = first_bad
            print(
                f"  frame {frame}: PNG MISMATCH {bad}/57344 pixels; first at "
                f"x={x} y={y} oracle={mine} idx={index:#05x} mame={theirs}"
            )
        else:
            print(f"  frame {frame}: PNG EXACT 57344/57344 pixels, {coverage}")

    (frame_dir / "index.txt").write_text(
        "\n".join(index_lines) + "\n", encoding="ascii"
    )

    if args.skip_png:
        print(f"PASS composite oracle emitted {len(selected)} frames (PNG check skipped)")
        return 0
    if png_failures:
        print(
            f"FAIL composite oracle: {png_failures}/{png_checked} frames "
            "disagree with the MAME screenshot"
        )
        return 1
    print(
        f"PASS composite oracle: {png_checked}/{png_checked} frames are "
        "pixel-exact against MAME's own screenshots "
        f"({png_checked * 57344} pixels)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
