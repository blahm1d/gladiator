#!/usr/bin/bash
# Queued Quartus build for Arcade-Gladiator.
#
# Implements the cross-session convention that the Wolf/Y/T/NARC sessions
# converged on 2026-07-28. Every rule below exists because a session broke
# something; the comments record which failure each one prevents.
set -uo pipefail

# Git Bash launched from PowerShell does not always inherit Git's Unix paths.
# Without these, /usr/bin/env cannot find bash and even cleanup tools such as
# rm are absent. Make the wrapper self-contained instead of depending on a
# login-shell launch convention.
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

QUEUE_DIR=/tmp/fpga_quartus.queue
LOCK_DIR=/tmp/fpga_quartus.lock
NOTIFY="$QUEUE_DIR/_notify.sh"
ME=gladiator
PROJECT=/d/deck/fpga/mister-gladiator
SNAP=
ticket_held=0
lock_held=0

log() { printf '[queued-build] %s\n' "$*"; }

live_quartus() {
    powershell.exe -NoProfile -Command \
        "@(Get-Process quartus_map,quartus_fit,quartus_sta,quartus_asm,quartus_sh,quartus -ErrorAction SilentlyContinue).Count" \
        2>/dev/null | tr -d '\r\n'
}

write_owner() {
    cat > "$LOCK_DIR/owner" <<EOF
$$
session=$ME
started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cmd=$*
EOF
}

release() {
    rc=$?
    trap - EXIT INT TERM

    # RULE 4 again, applied to ourselves: only release what names us.
    if [ "$lock_held" = "1" ] &&
       [ -f "$LOCK_DIR/owner" ] &&
       grep -q "session=$ME" "$LOCK_DIR/owner" 2>/dev/null; then
        n=$(live_quartus)
        if [ "${n:-0}" != "0" ]; then
            # A wrapper can die while a Windows stage survives it. Releasing
            # here would tell the next session the box is free while an orphan
            # is still fitting. Preserve the lock for explicit recovery.
            log "NOT releasing: $n quartus_* process(es) still alive"
            "$NOTIFY" note "$ME" \
                "wrapper exited rc=$rc but Quartus remains alive; lock held" ||
                true
        else
            rm -rf "$LOCK_DIR"
            "$NOTIFY" release "$ME" "$rc" || true
            log "lock released"
        fi
    elif [ "$lock_held" = "1" ]; then
        log "NOT releasing: owner file does not name $ME"
    fi

    if [ "$ticket_held" = "1" ]; then
        "$NOTIFY" dequeue "$ME" || true
        log "FIFO ticket released"
    fi

    # Legacy token cleanup. A bare token is no longer a queue claim.
    rm -f "$QUEUE_DIR/$ME"
    if [ -n "$SNAP" ]; then
        chmod +w "$SNAP" 2>/dev/null
        rm -f "$SNAP" 2>/dev/null
    fi
    log "queue token cleared, snapshot removed"
    exit "$rc"
}
trap release EXIT INT TERM

# The notifier is the versioned FIFO implementation, not merely an event log.
# Refuse to build if it is absent: silently degrading to the old race defeats
# the reason this wrapper exists.
if [ ! -x "$NOTIFY" ]; then
    log "FATAL: $NOTIFY is absent or not executable."
    log "Restore it from segamodel1/phase0/tools/quartus_notify.sh."
    exit 1
fi

"$NOTIFY" enqueue "$ME" $$ >/dev/null || {
    log "FATAL: could not enqueue FIFO ticket"; exit 1; }
ticket_held=1
if ! "$NOTIFY" holds "$ME"; then
    log "FATAL: FIFO ticket vanished immediately; refusing an unordered build."
    exit 1
fi
log "FIFO ticket verified"

# Wait safely: the FIFO determines ordering, while the lock and process check
# still determine actual ownership/liveness. Never delete somebody else's
# lock, even when its recorded PID appears dead.
while :; do
    if ! "$NOTIFY" holds "$ME" >/dev/null 2>&1; then
        log "FATAL: FIFO ticket was reaped while waiting."
        exit 1
    fi
    if ! "$NOTIFY" myturn "$ME" >/dev/null 2>&1; then
        log "waiting for an earlier FIFO ticket"
        sleep 10
        continue
    fi

    n=$(live_quartus)
    if [ "${n:-0}" != "0" ]; then
        log "waiting: $n quartus_* process(es) alive"
        sleep 10
        continue
    fi

    # RULE 2 -- mkdir is the only atomic claim primitive here.
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        lock_held=1
        break
    fi

    log "waiting: shared lock is present; owner:"
    cat "$LOCK_DIR/owner" 2>/dev/null ||
        log "(no owner file -- still NOT ours to break)"
    sleep 10
done

# RULE 2/3 -- write the owner file immediately after the atomic claim.
write_owner "preparing immutable PowerShell snapshot"
"$NOTIFY" acquire "$ME" || true

# RULE 7 -- run from an immutable snapshot.  Bash reads a script by byte offset
# while running it; editing it live makes the running instance resume mid-token
# (T-unit's helper degenerated into `hetools` / `low: command not found` and the
# corrupted control flow is what broke WOLF's lock).  `bash -n` does not catch
# this -- it checks the file, not the running process.
# build-quartus.ps1 derives the project from its OWN location
# ($project = Split-Path -Parent $PSScriptRoot), so the snapshot must live in
# the project's scripts/ dir. Snapshotting to /tmp made Quartus compile an empty
# temp directory and fail in 6s -- found the hard way, because the earlier live
# test only exercised the REFUSE path, never the build path. A positive control
# proves the instrument can refuse; it does not prove it can build.
SNAP="$PROJECT/scripts/.build-snapshot-$$.ps1"
cp "$PROJECT/scripts/build-quartus.ps1" "$SNAP" || {
    log "FATAL: build-quartus.ps1 not found"; exit 1; }
chmod -w "$SNAP" 2>/dev/null || true
log "snapshot: $SNAP"

write_owner "powershell $SNAP"
log "claimed the box; starting fit"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$SNAP"
rc=$?

log "quartus exit=$rc"
exit $rc
