#!/usr/bin/env python3
"""Build an ordered main-board write stream from the MAME trace."""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVENTS = ROOT / "sim/out/mame-full-events.csv"
OUTPUT = ROOT / "sim/out/mame-main-write-oracle.txt"
MAX_TICK12M = 30_000_000


def main() -> int:
    if not EVENTS.is_file():
        raise SystemExit(f"missing MAME event trace: {EVENTS}")

    count = 0
    last_tick = 0
    with EVENTS.open(newline="", encoding="ascii") as source, OUTPUT.open(
        "w", newline="\n", encoding="ascii"
    ) as output:
        reader = csv.DictReader(source)
        for row in reader:
            tick = int(row["tick12m"])
            if tick > MAX_TICK12M:
                break
            if row["kind"] != "write":
                continue
            domain = row["domain"]
            if domain == "main_mem":
                kind = "M"
            elif domain == "main_io":
                kind = "I"
            else:
                continue
            output.write(
                f"{kind} {int(row['address'], 16):04X} "
                f"{int(row['data'], 16):02X}\n"
            )
            count += 1
            last_tick = tick

    if count < 10_000 or last_tick < 28_000_000:
        raise SystemExit(
            f"incomplete main-write oracle: {count} writes through "
            f"tick {last_tick}"
        )
    print(
        f"wrote {OUTPUT} with {count} ordered main-board writes "
        f"through tick {last_tick}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
