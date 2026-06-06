# Changelog

All notable changes to Hermes-USB-Portable. Versions follow the `portable-vMAJOR.MINOR.PATCH` pin in `VERSION`.

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
