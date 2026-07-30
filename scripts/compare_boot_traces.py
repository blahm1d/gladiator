#!/usr/bin/env python3
"""Compare reconstructed CPU instruction addresses with MAME's oracle.

The RTL trace records every opcode-fetch cycle. Z80 prefix bytes therefore
appear as extra addresses while MAME prints one line per complete instruction.
The comparison permits at most two intervening RTL fetches; it does not permit
arbitrary resynchronization after a divergence.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path
import re


MAME_LINE = re.compile(r"^([0-9a-fA-F]{4}):")


def read_mame(path: Path) -> list[int]:
    addresses: list[int] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = MAME_LINE.match(line)
        if match:
            addresses.append(int(match.group(1), 16))
    return addresses


def read_board(path: Path) -> list[int]:
    with path.open(newline="", encoding="utf-8") as stream:
        return [int(row["address"], 16) for row in csv.DictReader(stream)]


def compare(name: str, mame: list[int], board: list[int], minimum: int) -> int:
    if not mame or not board:
        raise SystemExit(f"{name}: empty trace")

    try:
        board_index = board.index(mame[0])
    except ValueError as error:
        raise SystemExit(
            f"{name}: MAME start {mame[0]:04x} absent from RTL trace"
        ) from error

    matched = 0
    actual_text = "end-of-trace"
    for expected in mame:
        window = board[board_index : board_index + 3]
        try:
            offset = window.index(expected)
        except ValueError:
            actual = board[board_index] if board_index < len(board) else None
            actual_text = "end-of-trace" if actual is None else f"{actual:04x}"
            break
        board_index += offset + 1
        matched += 1
        if board_index >= len(board):
            break

    print(
        f"{name}: matched {matched} consecutive MAME instructions "
        f"against {len(board)} RTL opcode fetches"
    )
    if matched < minimum:
        raise SystemExit(
            f"{name}: divergence after {matched} instructions; "
            f"MAME expected {mame[matched]:04x}, RTL had {actual_text}"
        )
    return matched


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    parser.add_argument("--minimum", type=int, default=256)
    args = parser.parse_args()

    pairs = {
        "main Z80": ("mame-main.tr", "board-main-opcodes.csv"),
        "sound Z80": ("mame-sound.tr", "board-sound-opcodes.csv"),
        "audio 6809": ("mame-6809.tr", "board-6809-opcodes.csv"),
    }
    for name, (mame_name, board_name) in pairs.items():
        compare(
            name,
            read_mame(args.out / mame_name),
            read_board(args.out / board_name),
            args.minimum,
        )
    print("PASS MAME/RTL boot instruction comparison")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
