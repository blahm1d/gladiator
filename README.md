# GLADIATOR
### One core. One cabinet. No mercy.

This is Gladiator rebuilt in logic, not in nostalgia theater. The board model
stays honest: native refresh, native sync, no frame-rate conversion, and no
retimer sneaking in to “help” where it was never asked.

This repo is the source drop. Nothing decorative. Nothing ambiguous. The RTL,
support scripts, and simulation collateral are here because they are part of the
machine.

* * *

## THE DEAL

The core keeps the board’s timing path intact and leaves the game behaving like
the game, not like a softened imitation.

- CRT Adjust is core-side and optional.
- The read-rate generator resets from `hs_ref_out`.
- The sound-effects path is lifted without dragging speech or music with it.
- The release is meant to be measured, not guessed at.

* * *

## WHAT’S IN HERE

- `Arcade-Gladiator.sv`
- `Arcade-Gladiator.qsf`
- `Arcade-Gladiator.qpf`
- `Arcade-Gladiator.sdc`
- `files.qip`
- `rtl/`
- `scripts/`
- `sim/`
- `sys/`
- `cfg/`

* * *

## BUILD

From the project root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-quartus.ps1
```

That path is the one that matters.

* * *

## NOTES

- Native refresh stays native.
- Native sync stays native.
- CRT Adjust is gated by the OSD and defaults off.
- Sound effects can be lifted without rewriting the whole mix.

If you want the full story, read the source and the evidence. The README is the
front door, not the whole building.
