#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

exec sim/out/verilator-ucpu/Vtb_ucpu_host_replay \
    +SIM_SPEED_LOG2="${SIM_SPEED_LOG2:-4}" \
    +GAPCAP="${GAPCAP:-4000}" \
    +POLL_LIMIT="${POLL_LIMIT:-500000}" \
    "$@"
