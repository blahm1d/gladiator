#!/usr/bin/env python3
"""Build an MSM5205 replay oracle from Gladiator's MAME pin trace."""

from __future__ import annotations

import argparse
import csv
import math
from fractions import Fraction
from pathlib import Path


INDEX_SHIFT = (-1, -1, -1, -1, 2, 4, 6, 8)
CAPTURE_DELAY_12M = Fraction(6 * 12_000_000, 455_000)


class Msm5205:
    def __init__(self) -> None:
        self.signal = 0
        self.step = 0

    def capture(self, nibble: int, reset: bool) -> int:
        if reset:
            self.signal = 0
            self.step = 0
        else:
            step_value = math.floor(16.0 * math.pow(11.0 / 10.0, self.step))
            magnitude = step_value // 8
            if nibble & 1:
                magnitude += step_value // 4
            if nibble & 2:
                magnitude += step_value // 2
            if nibble & 4:
                magnitude += step_value
            if nibble & 8:
                magnitude = -magnitude

            self.signal = max(-2048, min(2047, self.signal + magnitude))
            self.step = max(
                0, min(48, self.step + INDEX_SHIFT[nibble & 7])
            )

        # MSM5205 is the 10-bit-DAC part. Its decoder is 12-bit internally.
        return self.signal & ~3


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    parser.add_argument("--events", default="mame-full-events.csv")
    parser.add_argument("--maximum-captures", type=int, default=4096)
    args = parser.parse_args()

    source = args.out / args.events
    target = args.out / "mame-adpcm-oracle.txt"
    decoder = Msm5205()
    control = 0
    pending_capture: Fraction | None = None
    captures: list[tuple[int, int, int]] = []

    def capture_current() -> None:
        reset = (control >> 5) & 1
        nibble = control & 0x0F
        captures.append((reset, nibble, decoder.capture(nibble, bool(reset))))

    with source.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            if row["domain"] != "adpcm" or row["kind"] != "write":
                continue
            write_time = Fraction(int(row["tick12m"]), 1)
            if pending_capture is not None and pending_capture <= write_time:
                capture_current()
                pending_capture = None
                if len(captures) >= args.maximum_captures:
                    break

            new_control = int(row["data"], 16)
            if (control & 0x10) and not (new_control & 0x10):
                pending_capture = write_time + CAPTURE_DELAY_12M
            control = new_control

    if (
        pending_capture is not None
        and len(captures) < args.maximum_captures
    ):
        capture_current()

    if len(captures) < min(1000, args.maximum_captures):
        raise SystemExit(
            f"captured only {len(captures)} MAME MSM5205 samples from {source}"
        )
    active_nibbles = {nibble for reset, nibble, _ in captures if not reset}
    if len(active_nibbles) < 12:
        raise SystemExit(
            f"MAME MSM5205 replay covers only {len(active_nibbles)} nibbles"
        )

    with target.open("w", encoding="ascii", newline="\n") as stream:
        for reset, nibble, sample in captures:
            stream.write(f"{reset} {nibble:X} {sample}\n")

    print(
        "PASS built MAME MSM5205 oracle: "
        f"{len(captures)} captures, {len(active_nibbles)} active nibbles"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
