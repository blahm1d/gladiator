#!/usr/bin/env python3
"""Compare RTL-generated board state with the exact MAME bus checkpoint."""

from pathlib import Path
import argparse
import sys


ROOT = Path(__file__).resolve().parents[1]
MAME_PATH = ROOT / "sim/out/mame-first-sprite-pass-state.txt"
RTL_PATH = ROOT / "sim/out/rtl-first-sprite-pass-state.txt"


def load_state(path: Path) -> dict[str, str]:
    if not path.is_file():
        raise SystemExit(f"missing state file: {path}")
    result: dict[str, str] = {}
    for line in path.read_text(encoding="ascii").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key] = value
    return result


def compare_hex_region(
    label: str, base: int, expected_hex: str, actual_hex: str
) -> int:
    expected = bytes.fromhex(expected_hex)
    actual = bytes.fromhex(actual_hex)
    if len(expected) != len(actual):
        print(
            f"FAIL {label} length: MAME={len(expected)} RTL={len(actual)}"
        )
        return 1
    mismatches = [
        (index, wanted, got)
        for index, (wanted, got) in enumerate(zip(expected, actual))
        if wanted != got
    ]
    if not mismatches:
        print(f"PASS {label}: {len(expected)} bytes exact")
        return 0
    first, wanted, got = mismatches[0]
    print(
        f"FAIL {label}: {len(mismatches)} mismatches; first at "
        f"{base + first:04X}, MAME={wanted:02X}, RTL={got:02X}"
    )
    for index, wanted, got in mismatches[:16]:
        print(f"  {base + index:04X}: MAME={wanted:02X} RTL={got:02X}")
    return 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mame", type=Path, default=MAME_PATH)
    parser.add_argument("--rtl", type=Path, default=RTL_PATH)
    parser.add_argument(
        "--label",
        default="the first completed sprite-RAM diagnostic sweep",
    )
    args = parser.parse_args()

    mame = load_state(args.mame)
    rtl = load_state(args.rtl)
    failed = 0

    for key in (
        "video_attributes",
        "latch",
        "sprite_buffer",
        "sprite_bank",
    ):
        wanted = mame.get(key)
        got = rtl.get(key)
        if wanted != got:
            print(f"FAIL {key}: MAME={wanted} RTL={got}")
            failed = 1
        else:
            print(f"PASS {key}={wanted}")

    failed |= compare_hex_region(
        "sprite RAM C000-CBFF",
        0xC000,
        mame["sprite_c000_cbff"],
        rtl["sprite_c000_cbff"],
    )
    failed |= compare_hex_region(
        "main state D000-F7FF",
        0xD000,
        mame["state_d000_f7ff"],
        rtl["state_d000_f7ff"],
    )

    if failed:
        print(
            "RESULT: RTL diverges from the MAME-generated board state at "
            f"{args.label}."
        )
        return 1
    print(
        f"RESULT: RTL-generated state exactly matches MAME at {args.label}."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
