# Updating Hermes-USB-Portable

This repo is a **portable wrapper** around
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent). The agent
source lives in `src/hermes-agent/` which is **gitignored** — the launchers download it
from upstream `main` on first run. `VERSION` records the exact upstream commit the
wrapper was last synced/verified against.

## Versioning scheme

`VERSION` pairs two numbers:

| Field | Meaning |
|---|---|
| `portable_version` (`portable-vX.Y.Z`) | The launcher/scripts/docs in **this** repo. Bump on wrapper changes. |
| `hermes_agent_commit` | The exact upstream `hermes-agent` commit `src/` is synced to. |

Tag releases as `portable-vX.Y.Z`. Bump: **patch** = launcher bugfix; **minor** = new
launcher feature / upstream sync; **major** = breaking layout/flow change.

## Sync from upstream + bump + push

```bash
# 0. From inside the portable folder (paths resolve relative to it).
ROOT="$(pwd)"            # or: ls -d /Volumes/*/Hermes-USB-Portable | head -1

# 1. Fetch the latest upstream and compare.
git clone --depth 1 https://github.com/NousResearch/hermes-agent /tmp/hermes-upstream
grep __version__ /tmp/hermes-upstream/hermes_cli/__init__.py
git -C /tmp/hermes-upstream rev-parse HEAD
diff -rq "$ROOT/src/hermes-agent" /tmp/hermes-upstream \
  -x .git -x __pycache__ -x '*.egg-info' -x '*.pyc' -x node_modules

# 2. Sync source (additive; preserves the editable-install egg-info).
rsync -a --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
  /tmp/hermes-upstream/ "$ROOT/src/hermes-agent/"

# 3. Refresh the editable install (best-effort; falls back to pip on exFAT).
RT="$ROOT/.cache/runtimes/$(uname -s | tr 'A-Z' 'a-z' | sed 's/darwin/macos/')-$(uname -m | sed 's/x86_64/x64/;s/arm64/arm64/')"
"$RT/uv/uv" pip install --python "$RT/venv/bin/python" --link-mode=copy -e "$ROOT/src/hermes-agent" "anthropic>=0.39.0" 2>/dev/null \
  || "$RT/venv/bin/python" -m pip install -e "$ROOT/src/hermes-agent" "anthropic>=0.39.0"

# 4. Verify on THIS OS (and on Windows separately with launch.bat).
bash launch.sh --version      # should say "Up to date"
bash launch.sh doctor         # expect all green except provider reachability
printf '5\n' | bash launch.sh # menu renders, brain detected, then exit

# 5. Record the pin + bump version, then commit & push.
#    Edit VERSION: hermes_agent_commit -> new HEAD, bump portable_version, synced_on.
git add VERSION docs/UPDATING.md launch.sh launch.bat scripts/
git commit -m "sync: hermes-agent -> <commit>; bump portable-vX.Y.Z"
git tag portable-vX.Y.Z
git push origin main --tags
```

## Rules

- **Never commit** `data/`, `.cache/`, `src/`, or `Brain/` (all gitignored — secrets,
  runtimes, agent source, and the personal vault stay off the public repo).
- **Test both launchers** before tagging: `launch.sh` (LF endings, macOS/Linux) and
  `launch.bat` (CRLF endings, Windows). Don't let an editor flip line endings.
- A clean reinstall is always available: delete `.cache/runtimes/<platform>` and
  `src/hermes-agent`, then run the launcher — it re-downloads upstream `main`.
