# Changelog

All notable changes to Hermes-USB-Portable. Versions follow the `portable-vMAJOR.MINOR.PATCH` pin in `VERSION`.

## [portable-v1.1.0] — 2026-06-06

### Added
- **Safe Eject** — new launcher menu option **`[5] Eject USB Safely`** (alias `e`) and a standalone engine `scripts/safe-eject.sh`. One action runs the full safe-removal workflow so the drive is never pulled with unsaved state:
  1. **Stop gateway** — releases live file handles (`hermes gateway stop`).
  2. **Save sessions** — counts/flushes `data/sessions/*` and appends a timestamped close-out entry to `Brain/log.md`.
  3. **Organise & verify the Brain** — scans all notes, runs a `[[wikilink]]` integrity check, and writes a machine-readable `Brain/.hermes-safe-eject.json` marker for the next AI session.
  4. **Sync** — double `sync` to flush all writes to the USB.
  5. **Eject** — detects the drive's volume (`df`) and ejects via a *detached* helper (macOS `diskutil eject`; Linux `udisksctl`/`umount`) so the volume isn't yanked out from under the running launcher.
- **Flags** on `scripts/safe-eject.sh`: `--dry-run` (save/organise/sync but skip eject) and `--yes` (no confirm prompt).
- `docs/SAFE-EJECT.md` — detailed workflow + troubleshooting.
- `.gitignore` now excludes macOS AppleDouble files (`._*`, `.DS_Store`).

### Notes
- A confirm prompt guards the action (cancel returns to the menu, exit code 10).
- Nothing is ever deleted; the workflow only saves, organises, and unmounts.
- Verified: `bash -n` syntax-clean; `--dry-run` exercised end-to-end (gateway stop, log close-out, 39-note Brain integrity scan, sync, volume detection).

## [portable-v1.0.0] — 2026-06-06
- Initial portable release: cross-platform launchers (`launch.sh`/`launch.bat`), fast model switcher, gateway + Telegram wiring, Obsidian "Brain", device recording, versioning + `docs/UPDATING.md`.
