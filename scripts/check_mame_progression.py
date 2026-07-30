#!/usr/bin/env python3
"""Verify the deterministic MAME run crosses a natural room transition."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    parser.add_argument("--minimum-frame", type=int, default=15000)
    args = parser.parse_args()

    path = args.out / "mame-full-frames.csv"
    with path.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    if not rows:
        raise SystemExit(f"no progression frames in {path}")
    if int(rows[-1]["frame"]) < args.minimum_frame:
        raise SystemExit(
            f"progression run ended at frame {rows[-1]['frame']}, "
            f"expected at least {args.minimum_frame}"
        )

    gameplay = [
        row
        for row in rows
        if int(row["frame"]) >= 600
        and int(row["stage_select_state"], 16) == 1
    ]
    if not gameplay:
        raise SystemExit("stage-1 gameplay state was never reached")

    # In the pinned MAME/ROM set, F440 is one while the room is active. It
    # drops to zero while the game replaces tile/sprite state, then returns
    # to one in the next playable room.
    transition_start = next(
        (
            row
            for row in gameplay
            if int(row["frame"]) >= 6000
            and int(row["scene_state"], 16) == 0
        ),
        None,
    )
    if transition_start is None:
        raise SystemExit("deterministic player did not enter a room transition")
    transition_frame = int(transition_start["frame"])

    next_room = next(
        (
            row
            for row in gameplay
            if int(row["frame"]) > transition_frame
            and int(row["scene_state"], 16) == 1
        ),
        None,
    )
    if next_room is None:
        raise SystemExit("room transition did not return to active gameplay")

    next_frame = int(next_room["frame"])
    if next_frame - transition_frame > 600:
        raise SystemExit(
            "room transition exceeded ten seconds: "
            f"{transition_frame} to {next_frame}"
        )

    before = next(
        row
        for row in reversed(gameplay)
        if int(row["frame"]) < transition_frame
        and int(row["scene_state"], 16) == 1
    )
    if (
        before["main_work_hash"] == next_room["main_work_hash"]
        or before["sprite_hash"] == next_room["sprite_hash"]
    ):
        raise SystemExit("room transition did not replace video/game state")

    print(
        "PASS MAME natural progression: "
        f"stage 1 transition at frame {transition_frame}, "
        f"next room active at frame {next_frame}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
