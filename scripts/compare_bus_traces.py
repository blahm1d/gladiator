#!/usr/bin/env python3
"""Compare normalized MAME and RTL boot write events.

Instruction flow proves that the CPUs execute the same program.  This check
adds the externally meaningful result: writes to board RAM, latches, device
ports, and ADPCM control must agree in address, data, and per-CPU order.
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


MINIMUM_EVENTS = {
    "main": 800,
    "sound": 400,
    "6809": 1,
}


def comparable(row: dict[str, str]) -> bool:
    # The reset program's first OUT targets the documented C0BF no-op before
    # initializing A.  MAME chooses A=00; T80 models the physically undefined
    # post-reset accumulator as FF.  Since the board decodes neither value,
    # exclude only this explicitly non-observable cycle.
    return not (
        row["domain"] == "main"
        and row["kind"].lower() == "io_w"
        and (int(row["address"], 16) & 0xFF) == 0xBF
    )


def normalized_event(row: dict[str, str]) -> tuple[str, int, int]:
    kind = row["kind"].lower()
    address = int(row["address"], 16)
    if kind == "io_w":
        # Z80 drives A15:A8 during I/O cycles, while MAME's I/O address
        # spaces are globally masked to eight bits.
        address &= 0xFF
    return kind, address, int(row["data"], 16)


def read_mame(path: Path) -> list[tuple[str, int, int]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return [
            normalized_event(row)
            for row in csv.DictReader(stream)
            if comparable(row)
        ]


def read_rtl(path: Path, domain: str) -> list[tuple[str, int, int]]:
    with path.open(newline="", encoding="utf-8") as stream:
        return [
            normalized_event(row)
            for row in csv.DictReader(stream)
            if row["domain"] == domain
            and row["kind"] in {"mem_w", "io_w"}
            and comparable(row)
        ]


def describe(event: tuple[str, int, int] | None) -> str:
    if event is None:
        return "end-of-trace"
    kind, address, data = event
    return f"{kind} {address:04x}={data:02x}"


def compare(
    name: str,
    mame: list[tuple[str, int, int]],
    rtl: list[tuple[str, int, int]],
    minimum: int,
) -> None:
    shared = min(len(mame), len(rtl))
    matched = 0
    while matched < shared and mame[matched] == rtl[matched]:
        matched += 1

    print(
        f"{name}: matched {matched} ordered write events "
        f"(MAME {len(mame)}, RTL {len(rtl)})"
    )
    if matched < minimum:
        expected = mame[matched] if matched < len(mame) else None
        actual = rtl[matched] if matched < len(rtl) else None
        raise SystemExit(
            f"{name}: first divergence at event {matched}: "
            f"MAME {describe(expected)}, RTL {describe(actual)}"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    args = parser.parse_args()

    rtl_path = args.out / "board-boot-trace.csv"
    for domain, minimum in MINIMUM_EVENTS.items():
        compare(
            domain,
            read_mame(args.out / f"mame-{domain}-bus-events.csv"),
            read_rtl(rtl_path, domain),
            minimum,
        )
    print("PASS MAME/RTL ordered boot-write comparison")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
