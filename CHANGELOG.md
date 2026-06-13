# Changelog

All notable changes to Hermes-USB-Portable. Versions follow the `portable-vMAJOR.MINOR.PATCH` pin in `VERSION`.

## [portable-v1.8.0] — 2026-06-13

### Changed — whole-stack update to latest (CVE / vuln-surface reduction)
Updated **everything** the portable drive ships, to shrink the vulnerability surface of the bundled
stack:

| Component | Was | Now |
|---|---|---|
| bundled **hermes-agent** | `0.16.0 @56236b16` | `0.16.0 @4b646bc2` (upstream `main` HEAD — newer commits/fixes) |
| **Python** | 3.11.15 (build 20260510) | **3.13.14** (build 20260610) |
| **Node.js** | 22.14.0 | **24.16.0** (LTS "Krypton") |
| **uv** | 0.7.8 | **0.11.21** |
| **ripgrep** | 14.1.1 | **15.1.0** |

- Python stays within hermes-agent's `requires-python = ">=3.11,<3.14"` — 3.13.14 is the newest
  allowed. All Python deps (`hermes-agent[all]` + `anthropic` + `python-telegram-bot`) build and
  install cleanly on 3.13.
- **Fixed a stale/abandoned Windows pin:** `scripts/setup-windows.ps1` was downloading Python from
  the **deprecated `indygreg/python-build-standalone`** org at **3.11.10 (20241016)**. Repointed to
  `astral-sh` 3.13.14 (20260610), matching `setup-unix.sh`. uv on Windows was also far behind (0.6.8).
- Version pins are now single-sourced as variables (`PY_VER`/`NODE_VER`/`UV_VER`/`RG_VER`) at the top
  of `setup-unix.sh`; `VERSION` records the exact runtime versions alongside the hermes-agent commit.

### Security
- **Re-audited the git repo for secrets — clean.** Only 21 files are tracked (launchers/docs/scripts);
  every sensitive path (`data/`, `Brain/`, `config.yaml`, `chrome-profile/`, `data/auth/`, the on-drive
  `.cache/unix-home/.git-credentials`) is gitignored. No API keys/tokens/passwords in tracked files or
  in the full commit history; no `.env`/key file was ever committed. The only matches are the owner's
  own public git-config email and download URLs.

### Notes
- **Verified on Linux (AST-WKS-571, Ubuntu 26.04, exFAT USB):** full clean rebuild — Python 3.13.14,
  Node v24.16.0, uv 0.11.21, ripgrep 15.1.0 all install via the exFAT-safe path; `ready.flag` written;
  `launch.sh --version` → Hermes v0.16.0 on **Python 3.13.14**; live NVIDIA `deepseek-v4-flash`
  one-shot through `launch.sh -z` returns a real reply. macOS/Windows setup scripts updated in lock-step
  (URLs verified to resolve) but not re-run on those OSes this session.
- Playwright browser binaries still don't unpack on exFAT-Linux (symlink-based) — non-fatal, unchanged.

## [portable-v1.7.0] — 2026-06-13

### Added
- **"NVIDIA — DeepSeek V4" model option** in the model switcher — `launch.sh` `[M]` menu **`[1]`** (and `launch.bat` parity). It wires hermes-agent's **native `nvidia` NIM provider**, which reads `NVIDIA_API_KEY` and has the endpoint (`https://integrate.api.nvidia.com/v1`) built in, so no base-url/key juggling is needed. Picking it prompts for a model (default below) and, if `NVIDIA_API_KEY` isn't already in `data/.env`, for the key (free at <https://build.nvidia.com/>).
- This gives the drive a **free, working model out of the box** — which matters because the prior default `kimi-for-coding` is **quota-exhausted (HTTP 403)** and the OpenRouter/Nous fallbacks are out of credit, so live chat was effectively dead until now.

### Changed
- **Default NVIDIA model is `deepseek-ai/deepseek-v4-flash`**, not `-v4-pro`. Reason — verified on Linux:
  - `deepseek-ai/deepseek-v4-flash` → hermes one-shot returns a real answer (`"NVIDIA OK"`, exit 0); fast first token. ✅
  - `deepseek-ai/deepseek-v4-pro` → **stalls**. hermes logs: `Stream stale for 180s — no chunks received. model=deepseek-ai/deepseek-v4-pro context=~33,607 tokens. Killing connection.` → `APIConnectionError`, all 3 retries fail. v4-pro runs in full **thinking mode**, and with Hermes' large system+tools+Brain context it doesn't emit a first token before the 180s stream-stale watchdog fires. It's still **typeable** in the menu (type `deepseek-ai/deepseek-v4-pro`) for short-context use, just not the default.
- The `[M]` menu was renumbered to put NVIDIA first: `[1]` NVIDIA, `[2]` Kimi, `[3]` Ollama, `[4]` LM Studio, `[5]`/`[6]` Gemini (OAuth / API key), `[7]` OpenRouter, `[8]` Anthropic, `[9]` Custom, `[10]` Full picker, `[11]` Back. `launch.bat` mirrors this.

### Notes
- The live default on the master drive was switched to `provider: nvidia` / `deepseek-ai/deepseek-v4-flash` and **verified end-to-end** (`launch.sh -z "…"` returns a real model reply on Ubuntu 26.04, exFAT). `NVIDIA_API_KEY` was already present in `data/.env`.
- To enable v4-pro properly one would need to pass NVIDIA's `extra_body={"chat_template_kwargs":{"thinking":false}}` (disables the reasoning trace) through the provider — not currently exposed by the launcher; flash sidesteps it entirely.
- `launch.bat` parity was added by mirroring the `launch.sh` flow (new `:mdl_nvidia` label, `findstr` check for an existing `NVIDIA_API_KEY`); it was **not re-run on Windows in this session** (no Windows host available) — macOS/Linux `launch.sh` is the verified path.

## [portable-v1.6.0] — 2026-06-13

### Fixed
- **`launch.sh` failed on the very first run on Linux — Hermes never started.** First-run setup aborted while unpacking the portable runtime with a flood of:
  ```
  tar: bin/python: Cannot create symlink to 'python3.11': Operation not permitted
  tar: lib/libpython3.11.so: Cannot create symlink to 'libpython3.11.so.1.0': Operation not permitted
  ...
  ```
  **Root cause:** the master USB is formatted **exFAT** (the only filesystem Windows + macOS + Linux can all read/write), and on **Linux the exFAT driver cannot store POSIX symlinks** — `ln -s` returns `EPERM`, and so does `tar -x` on any archive that contains symlinks. The portable Python (python-build-standalone) and Node tarballs are both symlink-heavy (`bin/python → python3.11`, `lib/libpython3.11.so → …so.1.0`, npm/npx/corepack, hundreds of terminfo entries). So `extract_tgz`/`extract_txz` died mid-unpack, `setup-unix.sh` exited non-zero, **`ready.flag` was never written**, and every subsequent `./launch.sh` re-entered the same broken setup. (macOS's exFAT implementation *does* support symlinks, which is why the existing macOS runtime — all real files — worked and Linux never had.)
- **Fix — materialise symlinks as real files on no-symlink drives.** `scripts/setup-unix.sh` now:
  - **Detects** whether the runtime drive can hold symlinks (a one-shot `ln -s` probe). On exFAT/NTFS it prints a clear `[WARN]` and switches strategy.
  - **Extracts on the host's local disk** (`/tmp`, where symlinks work) and copies the result onto the drive with **`cp -RL`** (dereference) so every symlink becomes a **real file** exFAT can store. Native filesystems (macOS/HFS, ext4) keep the original fast direct-extract path. This is applied to **Python, Node, uv, ripgrep, and the Hermes source tarball**.
  - **Builds the venv on local disk** for no-symlink drives (a venv is built out of symlinks to the base interpreter) and records the location in **`venv.path`** — the exact pointer `launch.sh` already reads and rebuilds from after a reboot purges `/tmp`. On native filesystems the venv stays on the drive.
  - Hardened incidental bugs surfaced along the way: ripgrep extraction no longer aborts the whole script under `set -e` on a man-page symlink; `uv`/`uvx` are dereferenced too; a `warn` call that ran before the function was defined was removed.

### Notes
- **macOS `launch.sh` / `setup-unix.sh` behaviour is unchanged** — the new branches only trigger when the drive can't store symlinks. Windows (`launch.bat`) is untouched.
- **Playwright browser binaries** still can't install onto exFAT-Linux (they unpack with symlinks); this is non-fatal and already wrapped in a warning — browser/web-automation tools are limited there, everything else works.
- **Verified on `AST-WKS-571` (Ubuntu 26.04 LTS, x86_64, exFAT USB):** clean `bash -n`; full first-run setup completes (Python/Node/uv/ripgrep/source all extract, venv built at `/tmp/hermes-portable-venv-<id>`, deps installed, `ready.flag` written); `bash launch.sh --version` → `Hermes Agent v0.16.0`, Python 3.11.15; `bash launch.sh doctor` runs (exit 0); the interactive menu renders and exits cleanly; device memory recorded to `Brain/devices/ast-wks-571-linux-x64.md`; plugin discovery reports **38 found, 32 enabled**. The agent loop reaches the model provider and fails only at the billing layer (`kimi-for-coding` → **HTTP 403 quota exhausted**, fallbacks out of credit) — an account/quota matter identical across OSes, not a launcher bug. Refill the Kimi quota or point `[M] → Model` at a funded provider for live chat.

## [portable-v1.5.0] — 2026-06-10

### Changed
- **README overhaul** — front-page completely rewritten to document every portable-specific feature shipped since v1.0.0. New sections added:
  - **Obsidian Brain Setup** — how to open `Brain/` as an Obsidian vault on any machine, vault structure, and the `.hermes-safe-eject.json` marker.
  - **Portable Chrome Launcher** — import profile from host, launch with `chrome-launcher/chrome.bat`, carry logins/bookmarks across PCs.
  - **Dashboard** — `[D] Open Dashboard` shortcut, cold-start wait logic, pre-built SPA, and security notes.
  - **Safe Eject** — `[5] Eject USB Safely` workflow, `--dry-run` / `--yes` flags, and eject-blocked troubleshooting.
  - **Model Switcher & OAuth Gemini** — `[M]` menu and `[4] Google Gemini — login with Google` with credential location.
  - **Versioning & Releases** — how `VERSION` pairs the wrapper with the upstream hermes-agent commit, plus tag history.
  - Updated mermaid diagram to include Brain, Dashboard, and Chrome Launcher nodes.
  - Updated directory structure YAML to include `Brain/`, `chrome-launcher/`, `docs/`, `chrome-profile/`, `chrome-downloads/`, `data/auth/`, and `scripts/safe-eject.sh`.
  - New troubleshooting entries for dashboard blank page, Chrome profile import, and USB eject blocked.
- No launcher or script code changes in this release — purely documentation and repo hygiene.

## [portable-v1.4.1] — 2026-06-07

### Fixed
- **`launch.bat -z "<multi-word prompt>"` (and any quoted passthrough args) crashed** with `is was unexpected at this time` before Hermes ever ran. Root cause: the direct-run path used `if not "%ARGS%"=="" ( hermes %ARGS% )`, which expands `%ARGS%` at *parse* time — so quotes/commas/parens inside the prompt got re-parsed as batch syntax and broke the `if`-block. Now it detects passthrough args via `%~1` and runs `hermes !ARGS!` on a bare line with **delayed expansion**, so the prompt reaches Hermes verbatim. Verified on LEGION: `launch.bat -z "In 8 words: your name, owner, and brain folder (no tools)."` runs clean and Herme replies. (Caveat: a literal `!` in the prompt is consumed by delayed expansion.) macOS `launch.sh` already handled this correctly via `bash`.

## [portable-v1.4.0] — 2026-06-07

### Fixed
- **Windows launcher had no OAuth Gemini option — "Login with Google" only worked on macOS.** The `[4] Google Gemini` entry in `launch.bat` ran the **API-key** path (`switch-model.py --provider gemini --set-env GEMINI_API_KEY=…`), even though the `google-gemini-cli` **OAuth** flow shipped in `launch.sh` back at v1.2.0. Result on Windows: users who had logged in with Google (creds at `data/auth/google_oauth.json`) and selected `[M] → Gemini` got `provider: gemini` with an empty `GEMINI_API_KEY` → **"model provider failed."** `launch.bat` is now at parity with `launch.sh`.

### Added (Windows parity with `launch.sh`)
- **`[4] Google Gemini — login with Google (OAuth, no API key)`** in `launch.bat`: runs `hermes auth add google-gemini-cli` (browser PKCE sign-in; creds → `data/auth/google_oauth.json` on the USB), then points `config.yaml` at `provider: google-gemini-cli` via `switch-model.py` (no API key). Default model `gemini-3-flash-preview` (high RPM, snappy for an always-on agent; switch to `gemini-3-pro-preview` for heavy reasoning).
- The existing **API-key** Gemini path is preserved at **`[5] Google Gemini — cloud (API key)`**; OpenRouter/Anthropic/Custom/Full-picker/Back renumbered to `[6]…[10]`.
- The model menu now reads input with `set /p` instead of `choice` so the two-digit **`[10] Back`** is selectable.

### Notes
- macOS `launch.sh` is unchanged (it already had both Gemini options).
- Verified on `LEGION` (Windows 11): switched `config.yaml` to `google-gemini-cli` / `gemini-3-flash-preview`; `hermes doctor` shows Gemini OAuth logged in; live one-shots on both `gemini-3-pro-preview` and `gemini-3-flash-preview` returned correct answers (identity + injected memory); gateway reconnects to Telegram on Gemini. `gemini-3-pro-preview` is RPM-throttled on the standard tier (HTTP 429 with short reset windows) under rapid multi-step calls — flash avoids this.

## [portable-v1.3.1] — 2026-06-06

### Fixed
- **Dashboard opened a blank / "connection refused" page.** Root cause: the launcher ran `hermes dashboard` which auto-opened the browser *immediately*, but the server's cold start (plugin discovery off the USB) takes **~60-90s to bind** — so the browser loaded before the server existed and looked broken. The backend was always fine (verified: SPA + assets 200, token injected, `/api/config`·`/api/model/info`·`/api/sessions`·`/api/system/stats` all 200 + JSON).
- `menu_dashboard()` now starts the server **detached with `--no-open`**, polls `http://127.0.0.1:9119/api/status` until it actually responds (up to 120s, with progress dots), and **only then opens the browser**. Added an **"already running" fast-path** (re-opens the tab instead of spawning a second server) and clear stop guidance (`hermes dashboard --stop`).
- New helpers `_http_ok` (curl → bundled-python fallback) and `_open_url` (macOS `open` / Linux `xdg-open`) so readiness-polling and browser-open work on any host.

### Notes
- First launch is slow (~60-90s) because plugin discovery loads off the USB; subsequent launches are faster (OS cache) and the fast-path is instant. Verified end-to-end: ready after 62-74s, browser opens only when live, `/api/config → 200`.

## [portable-v1.3.0] — 2026-06-06

### Added
- **Hermes Dashboard** — new main-menu shortcut **`[D] Open Dashboard`**. Launches hermes-agent's web UI (config, API keys, sessions, in-browser chat) at **`http://127.0.0.1:9119`**, bound to localhost only. Runs `hermes dashboard --skip-build` so startup is instant and needs no Node/npm at runtime; Ctrl-C stops it and returns to the menu.
- **Frontend pre-built onto the drive** — the Vite/React SPA is built once into `src/hermes-agent/hermes_cli/web_dist/` (vite `outDir`), so the dashboard serves a static bundle. `web/node_modules` is kept on the drive too, so a future rebuild works offline. The launcher auto-builds on first run if the dist is missing.
- Backend deps (`fastapi`/`uvicorn`/`starlette`) already ship via `hermes-agent[all]`, which the launcher installs on every venv (re)build — so the dashboard survives temp-venv rebuilds.

### Notes
- **Security:** the dashboard binds to `127.0.0.1` only; on loopback the SPA carries an ephemeral session token injected at serve time, so `/api/*` writes require it (verified: `/api/config` 200 with token, 401 without). Never expose it with `--insecure` on an untrusted network.
- Verified end-to-end: `bash -n` clean; `npm run build` → `web_dist` (index.html + assets); live server returns `GET / → 200`, `/api/status → 200` (public), `/api/config` & `/api/sessions → 200` (authenticated), `401` without token; `--skip-build`, `--stop`, `--status` all work.
- Gemini (v1.2.0) confirmed on the **subscription / standard-tier** via Cloud Code Assist (not API-key credits): `loadCodeAssist` reports `current_tier_id=standard-tier`, quota ~97% on the pro models, live inference OK.

## [portable-v1.2.0] — 2026-06-06

### Added
- **Google Gemini — Login with Google** — new model-menu entry **`[4] Google Gemini · login with Google (no API key)`**. Picks Gemini using a Google account instead of an API key, by wiring hermes-agent's native **`google-gemini-cli`** provider into the portable launcher:
  1. Runs `hermes auth add google-gemini-cli` — a browser **OAuth (PKCE)** sign-in to Google.
  2. Talks to Google's **Cloud Code Assist** backend (`cloudcode-pa.googleapis.com`) — the same backend behind Google's own gemini-cli free/subscription tiers. No API key, no `gemini-cli` install required (the public OAuth client ships with hermes-agent).
  3. Prompts for the model (default `gemini-3-pro-preview`; also `gemini-3.1-pro-preview`, `gemini-3-flash-preview`, `gemini-3.5-flash`) and points `data/config.yaml` at the provider.
- **Portable by design** — the OAuth credential is stored at `data/auth/google_oauth.json` (chmod 0600, on the USB and gitignored), so the login travels with the drive across machines.
- The existing **API-key** Gemini path is preserved, now at **`[5] Google Gemini · cloud (API key)`**; subsequent menu items renumbered (`[10] Back`).
- `docs/GEMINI-LOGIN.md` — setup, model notes, credential location, and the Google ToS caveat.

### Notes
- **Google policy:** using the gemini-cli OAuth client with third-party software is a ToS gray-area; hermes-agent shows an upfront warning before sign-in. Use with your own account at your discretion.
- Verified: `bash -n` syntax-clean; live Google sign-in completed end-to-end (`auth status google-gemini-cli: logged in`, credential saved on USB); model applied to `config.yaml`.

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
