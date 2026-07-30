#!/usr/bin/env python3
"""Validate that the deterministic MAME oracle exercises Gladiator audio.

This does not claim that a WAV comparison replaces circuit evidence. It
guards the golden capture itself: both sound generators must receive a
meaningful gameplay sequence, the externally clocked MSM5205 pins must toggle
through real nibble data, and MAME must have produced non-silent PCM.
"""

from __future__ import annotations

import argparse
import csv
import struct
import wave
from pathlib import Path


def pcm_peak(path: Path) -> tuple[int, int, int, float]:
    with wave.open(str(path), "rb") as stream:
        channels = stream.getnchannels()
        width = stream.getsampwidth()
        rate = stream.getframerate()
        frame_count = stream.getnframes()
        if width not in (1, 2, 3, 4):
            raise SystemExit(f"unsupported WAV sample width: {width} bytes")

        peak = 0
        while True:
            block = stream.readframes(32768)
            if not block:
                break
            if width == 1:
                peak = max(peak, max(abs(value - 128) for value in block))
            elif width == 2:
                samples = struct.iter_unpack("<h", block)
                peak = max(peak, max(abs(value[0]) for value in samples))
            elif width == 3:
                for offset in range(0, len(block), 3):
                    value = int.from_bytes(
                        block[offset : offset + 3],
                        byteorder="little",
                        signed=True,
                    )
                    peak = max(peak, abs(value))
            else:
                samples = struct.iter_unpack("<i", block)
                peak = max(peak, max(abs(value[0]) for value in samples))

    duration = frame_count / rate
    return channels, rate, peak, duration


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("sim/out"))
    parser.add_argument("--minimum-frame", type=int, default=600)
    parser.add_argument("--events", default="mame-full-events.csv")
    parser.add_argument("--frames", default="mame-full-frames.csv")
    parser.add_argument("--wav", default="mame-full-audio.wav")
    args = parser.parse_args()

    event_path = args.out / args.events
    frame_path = args.out / args.frames
    wav_path = args.out / args.wav

    with frame_path.open(newline="", encoding="utf-8") as stream:
        frame_rows = list(csv.DictReader(stream))
    if not frame_rows or int(frame_rows[-1]["frame"]) < args.minimum_frame:
        raise SystemExit("MAME audio oracle did not reach the required frame")

    ym_writes = 0
    gameplay_ym_writes = 0
    ym_registers: set[int] = set()
    adpcm_writes = 0
    falling_edges = 0
    reset_releases = 0
    bank_values: set[int] = set()
    captured_nibbles: set[int] = set()
    previous_adpcm = 0

    with event_path.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            domain = row["domain"]
            kind = row["kind"]
            frame = int(row["frame"])
            data = int(row["data"], 16)

            if domain == "ym2203" and kind == "register":
                ym_writes += 1
                ym_registers.add(int(row["address"], 16))
                if frame >= 420:
                    gameplay_ym_writes += 1
            elif domain == "adpcm" and kind == "write":
                adpcm_writes += 1
                bank_values.add((data >> 6) & 1)
                if (previous_adpcm & 0x20) and not (data & 0x20):
                    reset_releases += 1
                if (previous_adpcm & 0x10) and not (data & 0x10):
                    falling_edges += 1
                    if not (data & 0x20):
                        captured_nibbles.add(data & 0x0F)
                previous_adpcm = data

    if ym_writes < 100 or gameplay_ym_writes < 25:
        raise SystemExit(
            "YM2203 trace is too small to cover boot and gameplay audio: "
            f"{ym_writes} total, {gameplay_ym_writes} after Start"
        )
    if len(ym_registers) < 16:
        raise SystemExit(
            f"YM2203 trace touched only {len(ym_registers)} registers"
        )
    if adpcm_writes < 100 or falling_edges < 25:
        raise SystemExit(
            "MSM5205 pin trace did not exercise enough external-VCLK data: "
            f"{adpcm_writes} writes, {falling_edges} falling edges"
        )
    if reset_releases == 0:
        raise SystemExit("MSM5205 reset was never released")
    if len(captured_nibbles) < 8:
        raise SystemExit(
            "MSM5205 captured too little nibble diversity: "
            f"{len(captured_nibbles)} values"
        )

    channels, rate, peak, duration = pcm_peak(wav_path)
    required_seconds = args.minimum_frame / 60.0
    if duration < required_seconds - 0.25:
        raise SystemExit(
            f"MAME WAV is only {duration:.3f}s; expected {required_seconds:.3f}s"
        )
    if peak == 0:
        raise SystemExit("MAME WAV is silent")

    print(
        "PASS MAME audio oracle: "
        f"{ym_writes} YM writes/{len(ym_registers)} registers, "
        f"{falling_edges} MSM5205 captures/{len(captured_nibbles)} nibbles, "
        f"banks={sorted(bank_values)}, reset releases={reset_releases}, "
        f"WAV={channels}ch {rate}Hz {duration:.3f}s peak={peak}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
