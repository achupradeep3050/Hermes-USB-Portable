# <p align="center">🛸 Hermes Agent — Portable for Windows</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows_10_%2F_11_x64-0078D4?style=for-the-badge&logo=windows" alt="Windows">
  <img src="https://img.shields.io/badge/Launcher-hermes.cmd-8A2BE2?style=for-the-badge" alt="hermes.cmd">
  <img src="https://img.shields.io/github/license/NousResearch/hermes-agent?style=for-the-badge&color=2563EB" alt="License">
</p>

---

<p align="center">
  <strong>Run a fully self-contained AI agent from a single folder or USB stick — and talk to it exactly like the real CLI.</strong><br>
  No global installation. No host pollution. Every conversation, key, memory and skill stays inside the folder.
</p>

This is the **Windows edition** of the portable build. It documents `hermes.cmd`, the
lightweight launcher that sits next to the old `launch.bat` menu. The cross-platform
description, macOS and Linux instructions and the Ventoy section live in
[README.md](README.md).

---

## What's new: `hermes.cmd`

`launch.bat` is a menu. It handles first-run setup, repair, update, the gateway and settings
in one place — but it is overloaded, and it ignores most of `hermes.exe`'s own arguments.
`hermes -c`, `hermes sessions list`, `hermes update --check` or `hermes --tui` have no route
through it.

`hermes.cmd` is a thin launcher that mirrors the CLI instead of replacing it:

| Call | Behaviour |
|---|---|
| `hermes` | interactive chat — `--yolo`, resumes the latest session, workspace = the folder you called it from |
| `hermes start` | messaging gateway in the foreground (`gateway run`) |
| `hermes update` | installs the pinned release, repairs the runtime, pulls pm packages and Playwright |
| `hermes update --check` | compares installed release, `VERSION` pin and origin pin |
| `hermes update --force` | rebuilds even when pin and installation already match |
| `hermes install` | full install/repair, then the setup wizard |
| `hermes launcher` | opens the old `launch.bat` menu (deprecated) |
| `hermes -h` / `--help` | this overview, then `-- More --`, then the complete `hermes --help` |
| anything else | passed to `hermes.exe` **unchanged** |

The last row is the point: `hermes -c`, `hermes -z "…"`, `hermes --tui`, `hermes sessions list`,
`hermes config get model.default`, `hermes logs -f`, `hermes gateway status` and every other
command or flag behave exactly as in a normal install.

Where a parameter cannot work unchanged in a portable installation, it is mapped to the
portable equivalent instead of failing:

*   `hermes update` follows the pin (`VERSION` → `src\hermes-agent\.portable-ref`); the official
    git-based update cannot work here because the source tree is a release tarball.
*   `hermes update --check` compares installed release, pin and `origin` (the official check
    answers "Not a git repository").
*   `hermes install` has no upstream counterpart — it runs `scripts\setup-windows.ps1`, the pm
    packages (bash, chromium), Playwright and finally `hermes setup`.
*   `hermes gateway` keeps its upstream meaning ("make sure a gateway runs"); the foreground
    variant is `hermes start`. `config` and `setup` are not intercepted at all.

Keywords only match when they stand alone: `hermes config get model.default`,
`hermes gateway status` and `hermes setup model` go straight to the CLI.

---

## Quick Start (Windows 10 / 11)

1.  Copy the folder to a USB stick or external SSD (exFAT or NTFS, at least 8 GB free).
2.  Open a terminal in that folder and run:

    ```bat
    hermes install
    ```

    The first run downloads about 600 MB (Python, Node, MinGit, uv), builds the venv, installs
    the pm packages including `bash`, adds Playwright with Chromium, and finishes with the
    setup wizard for providers and API keys.
3.  Start chatting:

    ```bat
    hermes
    ```

    This starts in the current directory and resumes the latest session there.

Optional: add the folder to your `PATH`. `hermes` then works from any directory, because
`hermes.cmd` resolves its own location and every path from it.

> Prefer the menu? `hermes launcher` (or a double-click on `launch.bat`) still opens the old
> launcher with setup, repair, update, gateway, dashboard, Chrome and the model switcher.

---

## Commands in detail

### `hermes` — interactive chat

Starts with `--yolo` and resumes the newest session for the current folder:

```bat
hermes                       :: chat, current folder, latest session, no approval prompts
hermes chat                  :: same CLI path, but without --yolo and without resume
hermes -c                    :: resume the latest session explicitly
hermes --resume latest       :: same as -c
hermes -z "hello"            :: one-shot prompt, plain text on stdout
```

The launcher never changes into `src\hermes-agent` for this, so the agent works in the folder
you started it from. `--no-restore-cwd` prevents the resume from jumping into the session's
old directory.

### `hermes update` — pin-based maintenance

```bat
hermes update                :: install the pinned release (and repair, if something is missing)
hermes update --check        :: compare installed release, VERSION pin and origin pin
hermes update --force        :: force the rebuild
hermes update --plan         :: pass the flag to the official update, unchanged
```

`--check` prints three lines and exits with `0` when everything matches, `1` when a release is
available:

```
Installed:         v0.23.3
Pin in VERSION:    v0.23.3
Pin on origin:     v0.23.3

[OK] Up to date - installed release, pin and origin agree.
```

Any other flag is handed to the official `hermes update` together with all remaining
arguments, so `--check`-style mistakes cannot trigger a rebuild by accident.

### `hermes install` — first run and repair

Runs the full portable installation: `scripts\setup-windows.ps1`, `hermes pm install`,
`hermes pm install git` (this is the `bash` Hermes needs for every shell command), Playwright
1.64.1 with Chromium, and finally the setup wizard.

Before rebuilding, the launcher probes the runtime with a rename test. If a running gateway or
an open chat holds the files, it stops the gateway, waits, probes again and starts the gateway
back up after the rebuild. If the folder stays locked, it stops with a clear message instead of
half-rebuilding.

### `hermes start` — gateway

```bat
hermes start                 :: foreground gateway (gateway run)
hermes gateway status        :: upstream command, passed through
hermes gateway stop          :: upstream command, passed through
```

### `hermes launcher` — the old menu

Kept for the features that only exist there (first-run menu, dashboard entry, Chrome profile
launcher, model switcher). Marked deprecated because `hermes.cmd` covers the CLI side.

---

## Environment

`hermes.cmd` sets the whole portable environment once, in the same way `launch.bat` does:

| Variable | Value |
|---|---|
| `HERMES_HOME` | `<folder>\data` |
| `PATH` | runtime venv, Python, Node, MinGit, uv, `bin` prepended |
| `PYTHONNOUSERSITE` | `1`; `PYTHONHOME` and `PYTHONPATH` empty |
| `APPDATA`, `LOCALAPPDATA`, `HOME` | `<folder>\.cache\windows-*` |
| `UV_CACHE_DIR`, `PIP_CACHE_DIR` | `<folder>\.cache\uv-cache`, `.cache\pip-cache` |
| `PLAYWRIGHT_BROWSERS_PATH` | `.cache\runtimes\windows-x64\playwright` |
| `OBSIDIAN_VAULT_PATH` | `<folder>\Brain`, when the vault exists |

`hermes.exe` is always called by absolute path — a bare `hermes` would resolve back to the
launcher. Exit codes are passed through unchanged, so scripts and pipelines can rely on them.

---

## Workspace layout (Windows)

```text
hermes-portable\
├── hermes.cmd                  # this launcher (CLI-shaped entry point)
├── launch.bat                  # legacy menu (setup, repair, dashboard, Chrome, models)
├── VERSION                     # portable_version + hermes_agent_ref pin
├── scripts\
│   └── setup-windows.ps1       # first-run installation and repair
├── chrome-launcher\            # portable Chrome profile (chrome.bat)
├── Brain\                      # Obsidian vault: memory, journals, skills
├── data\                       # [BACKUP THIS] all private state
│   ├── config.yaml             # providers and models
│   ├── .env                    # API keys (never commit this file)
│   ├── auth\                   # OAuth credentials
│   ├── sessions\               # chat histories
│   ├── tools\                  # pm packages, incl. PortableGit with bash.exe
│   ├── installs\               # pm environments
│   └── logs\                   # agent, gateway and dashboard logs
├── src\
│   └── hermes-agent\           # pinned release (tarball, no .git)
└── .cache\
    ├── runtimes\windows-x64\   # python, node, git, uv, venv, playwright
    ├── windows-home\           # redirected HOME
    ├── windows-appdata\        # redirected APPDATA
    ├── windows-localappdata\   # redirected LOCALAPPDATA
    ├── uv-cache\               # redirected uv cache
    └── pip-cache\              # redirected pip cache
```

Nothing of this is installed on the host: no registry entries, no `%USERPROFILE%\.hermes`, no
global packages.

---

## Updating the pin

`hermes_agent_ref` in `VERSION` is the one pin every script reads. To move it:

```bat
git -C <folder> pull          :: fetch the newer wrapper + pin (this changes VERSION)
hermes update                 :: install the pinned release, rebuild the venv
hermes update --check         :: verify installed = pin = origin
```

`hermes update` never touches the wrapper files (`launch.bat`, `launch.sh`, `docs\`,
`scripts\`). That is deliberate: the launcher repairs the installation, not the repository.

If a rebuild is needed while the runtime is in use, close the open chat or let the launcher
stop the gateway — Windows refuses to rename a directory whose DLLs are loaded.

---

## Dashboard

```bat
hermes dashboard             :: start the web UI
hermes dashboard --stop      :: stop it
hermes dashboard --status    :: list running dashboard processes
```

Hermes serves it on `127.0.0.1:9119` by default. The portable builds that start from
`launch.sh` reserve `9139` to stay clear of a Hermes installed on the host; to use the same
port here, set `HERMES_PORTABLE_DASHBOARD_PORT=9139` before starting. See
[docs/DASHBOARD.md](docs/DASHBOARD.md) for details and troubleshooting.

---

## Model selection and API keys

Keys live in `data\.env`, provider definitions in `data\config.yaml`:

```env
OPENROUTER_API_KEY=sk-or-v1-...
OPENAI_API_KEY=sk-proj-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=
```

Configure interactively with `hermes setup`, switch models with `hermes model`, or edit
`data\config.yaml` directly. `hermes config` opens the file in your editor, `hermes config get
model.default` prints a single value, `hermes config set model.default <name>` changes it.

The launcher menu (`hermes launcher`) still offers the model switcher, the Google and
subscription sign-ins, and the uncensored provider presets described in
[README.md](README.md).

---

## Safe eject

There is no Windows safe-eject script. Stop the gateway first, then eject through Explorer:

```bat
hermes gateway stop
```

After that, Windows releases the drive's file handles and the USB symbol in the tray ejects it
cleanly. The Unix workflow (`scripts/safe-eject.sh`) is described in
[README.md](README.md) and [docs/SAFE-EJECT.md](docs/SAFE-EJECT.md).

---

## Footprint

Measured on a full Windows x64 installation:

| Component | Size |
|---|---|
| Runtime (`python`, `node`, `git`, `uv`, venv) | ~1.1 GB |
| Playwright Chromium | ~0.7 GB |
| `data\tools` (pm packages, PortableGit) | ~1.7 GB |
| `data\installs` (pm environments) | ~1.9 GB |
| `src\hermes-agent` | ~50 MB |
| `data\` (sessions, memory, skills) | ~10 MB and growing |

Plan for **8 GB** free space on the stick, more if you keep many sessions or backups.

---

## Versioning

| Field | Meaning |
|---|---|
| `portable_version` | the wrapper in this folder (`portable-vX.Y.Z`) |
| `hermes_agent_ref` | the pinned release tag of `hermes-agent` |
| `hermes_agent_commit` | the exact upstream commit behind that tag |

Current pin: **portable-v1.9.2** with **hermes-agent v0.23.3** (`caafe538`), Python 3.14.9,
Node 24.16.0, uv 0.11.21, ripgrep 15.1.0, Playwright 1.64.1.

---

## Security advisory

> [!WARNING]
> Your portable folder contains your identity: `data\.env` holds raw API keys,
> `data\sessions\` holds your conversations, `data\auth\` holds OAuth credentials and
> `chrome-profile\` holds your browser identity. Anyone with the drive can use them.
>
> Encrypt the drive with **BitLocker** (Windows) or **VeraCrypt** (cross-platform), and avoid
> carrying production keys or large API balances on a stick you take everywhere.

---

## Troubleshooting & FAQ

<details>
<summary><strong>First run fails or times out</strong></summary>

*   The installation downloads about 600 MB from GitHub and the Node/Python CDNs. Corporate or
    school firewalls are the usual cause.
*   Delete `.cache\runtimes\windows-x64` and run `hermes install` again.
*   `hermes install` reports the failing step; the log is under `data\logs\`.
</details>

<details>
<summary><strong>"Access is denied" while updating — the runtime is locked</strong></summary>

*   A running gateway or an open chat holds `.cache\runtimes\windows-x64\python`. Windows then
    refuses to rename or replace the directory.
*   `hermes update` stops the gateway itself, waits and restarts it afterwards. If the folder
    stays locked, close the open Hermes window and run `hermes update` again.
*   `hermes gateway stop` releases the handles manually.
</details>

<details>
<summary><strong>"No shell found. Hermes needs bash (Git for Windows on Windows)"</strong></summary>

*   Hermes runs every shell command through `bash`; the MinGit from the setup only ships
    `git.exe`.
*   `hermes install` (or `hermes pm install git`) adds PortableGit with
    `data\tools\git-*\usr\bin\bash.exe`.
*   Check with `hermes pm status`.
</details>

<details>
<summary><strong>Web/Playwright tools fail</strong></summary>

*   Chromium is expected under `.cache\runtimes\windows-x64\playwright`; `hermes install`
    reinstalls it. Playwright is not part of the `all` extra, so a plain venv rebuild does not
    bring it back.
</details>

<details>
<summary><strong>`hermes update --check` says "Not a git repository"</strong></summary>

*   That is the official check answering for a tarball install. Use `hermes update --check`
    *without* further arguments — the launcher's own comparison then reports installed / pin /
    origin.
</details>

<details>
<summary><strong>`hermes` is not found</strong></summary>

*   The folder is not in your `PATH`. Either add it, or call `hermes.cmd` explicitly from the
    folder.
*   A `hermes` from another installation earlier in `PATH` wins over this folder; put the
    portable folder first.
</details>

<details>
<summary><strong>Ctrl+C during the help output asks "Batchvorgang abbrechen (J/N)?"</strong></summary>

*   That is `cmd.exe` asking about the running batch file, not Hermes. Answer `N` to continue
    with the rest of the help, `J` to abort.
</details>

<details>
<summary><strong>Windows Defender flags the launcher</strong></summary>

*   False positive: PowerShell downloads runtimes from GitHub and the Node/Python CDNs.
*   Choose "More info" → "Run anyway". The scripts are plain text under `scripts\`.
</details>

<details>
<summary><strong>Hermes feels slow from the stick</strong></summary>

*   USB 2.0 drives throttle Python imports. Use USB 3.0/3.1 or an external SSD.
*   A local copy of the folder is always faster than the stick.
</details>

---

## Credits & attribution

*   **[Hermes Agent](https://github.com/NousResearch/hermes-agent)** — the agent core, by
    [Nous Research](https://github.com/NousResearch).
*   **[Hermes-USB-Portable](https://github.com/achupradeep3050/Hermes-USB-Portable)** — the
    portable layout, setup scripts and docs this edition builds on.
*   **[python-build-standalone](https://github.com/astral-sh/python-build-standalone)**,
    **[uv](https://github.com/astral-sh/uv)** — portable interpreter and installer.
*   **[Obsidian](https://obsidian.md/)** — markdown vault behind the portable Brain.
