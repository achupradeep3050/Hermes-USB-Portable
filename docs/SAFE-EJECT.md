# Safe Eject — Workflow & Reference

`Eject USB Safely` (launcher option **[5]**, or run `scripts/safe-eject.sh`) saves and organises everything on the drive, then ejects it cleanly. Use it every time before removing the USB so you never lose session state or corrupt the Brain.

## Why this exists
The portable drive holds live state: Hermes **sessions** (`data/sessions/`), the **Obsidian Brain**, and (sometimes) a running **gateway**. Pulling the USB while those are open risks lost work or a half-written vault. This one action handles all of it.

## What it does (step by step)
```
[1] Stop gateway     hermes gateway stop        (releases live handles)
[2] Save sessions    flush data/sessions/*  +   append close-out to Brain/log.md
[3] Organise Brain   scan notes, verify [[wikilinks]], write .hermes-safe-eject.json
[4] Sync             sync; sync                 (flush writes to the USB)
[5] Eject            detect volume (df) -> eject via detached helper
```
- **macOS:** `diskutil eject "/Volumes/<NAME>"`
- **Linux:** `udisksctl unmount` + `power-off` (falls back to `umount`)

The eject runs from a small detached helper in `$TMPDIR` that waits ~1s for the launcher to exit, so the volume isn't pulled out from under the running script (which itself lives on the drive).

## How to use
**From the launcher**
```
./launch.sh   ->   [5] Eject USB Safely   ->   confirm [y]
```
**Standalone**
```bash
scripts/safe-eject.sh            # interactive
scripts/safe-eject.sh --yes      # skip the confirm prompt
scripts/safe-eject.sh --dry-run  # save/organise/sync but DON'T eject (safe to test)
```

## Safety guarantees
- **Confirm prompt** before anything happens (cancel = return to menu, exit code 10).
- **Nothing is deleted** — only save, organise, sync, unmount.
- **Read-only-safe** — even if auto-eject is blocked, the data is already synced, so a manual/force eject afterwards is safe.

## If it can't auto-eject
Something still holds the volume open. Common culprits and fixes:
| Holder | Fix |
|---|---|
| A shell `cd`'d into the drive | `cd ~` in that terminal |
| Obsidian app open on the Brain | Quit Obsidian |
| A VM / sandbox with the folder mounted | Disconnect the folder / end that session |
| Spotlight indexing (macOS) | `sudo mdutil -i off "/Volumes/<NAME>"` then retry |

Manual fallback (data is already synced, so this is safe):
```bash
# macOS
diskutil eject "/Volumes/<NAME>"        # or: diskutil unmountDisk force "/Volumes/<NAME>"
# Linux
udisksctl unmount -b /dev/sdX1 && udisksctl power-off -b /dev/sdX1   # or: sudo umount /media/<NAME>
```
Find what's holding it: `lsof "/Volumes/<NAME>"` (macOS) / `fuser -vm /media/<NAME>` (Linux).

## For AI agents reading the drive
After a clean eject, `Brain/.hermes-safe-eject.json` records `{last_safe_eject, notes, broken_links}` — use it to confirm the vault was saved consistently and to see the note count from the previous session.
