#!/bin/bash
# ============================================================================
# Hermes Agent - Portable Launcher (macOS / Linux)
# ============================================================================
# Terminal:   ./launch.sh
# macOS Finder: rename this file to "launch.command" for double-click support.
# On first run, it downloads ~600MB of runtime files automatically.
# All data stays in the "data/" folder — nothing touches the host computer.
# ============================================================================

set -e

# Resolve portable root (directory containing this script)
PORTABLE_ROOT="$(cd "$(dirname "$0")" && pwd)"
HERMES_HOME="$PORTABLE_ROOT/data"
CACHE_DIR="$PORTABLE_ROOT/.cache"
SRC_DIR="$PORTABLE_ROOT/src"

# ---------------------------------------------------------------------------
# Detect OS and architecture
# ---------------------------------------------------------------------------
OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
    Linux*)     PLATFORM="linux" ;;
    Darwin*)    PLATFORM="macos" ;;
    CYGWIN*|MINGW*|MSYS*) PLATFORM="windows" ;;
    *)
        echo "[ERROR] Unsupported operating system: $OS_RAW"
        exit 1
        ;;
esac

case "$ARCH_RAW" in
    x86_64|amd64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "[ERROR] Unsupported architecture: $ARCH_RAW"
        exit 1
        ;;
esac

RUNTIME_DIR="$CACHE_DIR/runtimes/${PLATFORM}-${ARCH}"

# ---------------------------------------------------------------------------
# Friendly device + OS identity (used in the dashboard and device memory)
# ---------------------------------------------------------------------------
DEVICE_HOST="$(hostname 2>/dev/null | cut -d. -f1)"
[ -z "$DEVICE_HOST" ] && DEVICE_HOST="unknown-host"
case "$PLATFORM" in
    macos)
        _osv="$(sw_vers -productVersion 2>/dev/null)"
        PRETTY_OS="macOS ${_osv:-} (${ARCH})" ;;
    linux)
        _osn="$( . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME" )"
        PRETTY_OS="${_osn:-Linux} (${ARCH})" ;;
    windows) PRETTY_OS="Windows (${ARCH})" ;;
    *) PRETTY_OS="${PLATFORM} (${ARCH})" ;;
esac
DEVICE_SLUG="$(echo "${DEVICE_HOST}-${PLATFORM}-${ARCH}" | tr ' /._' '----' | tr 'A-Z' 'a-z')"

# ---------------------------------------------------------------------------
# First-run setup
# ---------------------------------------------------------------------------
if [ ! -f "$RUNTIME_DIR/ready.flag" ]; then
    echo ""
    echo "============================================"
    echo "    Hermes Portable - First Run Setup"
    echo "============================================"
    echo "  Platform: ${PLATFORM}-${ARCH}"
    echo "  This will download ~600MB of runtime files."
    echo "  Please be patient."
    echo "============================================"
    echo ""
    bash "$PORTABLE_ROOT/scripts/setup-unix.sh" "$PORTABLE_ROOT"
    if [ $? -ne 0 ]; then
        echo ""
        echo "[ERROR] Setup failed. Please check your internet connection and try again."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Environment isolation — keep everything inside the portable folder
# (except the venv, which must live on a local FS to avoid exFAT hardlink
# limitations — see scripts/setup-unix.sh for details)
# ---------------------------------------------------------------------------

# Read the venv path from the pointer file written during setup.
if [ -f "$RUNTIME_DIR/venv.path" ]; then
    VIRTUAL_ENV="$(cat "$RUNTIME_DIR/venv.path")"
else
    # Fallback for older setups that put the venv on the drive.
    VIRTUAL_ENV="$RUNTIME_DIR/venv"
fi

# If the venv is missing (e.g. after a reboot purged $TMPDIR), rebuild it.
if [ ! -x "$VIRTUAL_ENV/bin/python" ]; then
    echo ""
    echo "[INFO] Local venv not found (temp was likely cleared). Rebuilding ..."
    echo "       This is fast because packages are cached on the drive."
    UV_EXE="$RUNTIME_DIR/uv/uv"
    PYTHON_EXE="$RUNTIME_DIR/python/bin/python3"
    SRC_DIR="$PORTABLE_ROOT/src"

    if [ "$PLATFORM" = "macos" ]; then
        LOCAL_BASE="${TMPDIR:-/tmp}"
    else
        LOCAL_BASE="/tmp"
    fi

    DRIVE_ID="$(echo "$RUNTIME_DIR" | md5sum 2>/dev/null | cut -c1-8 || echo "hermes")"
    VIRTUAL_ENV="${LOCAL_BASE}/hermes-portable-venv-${DRIVE_ID}"
    export UV_CACHE_DIR="${LOCAL_BASE}/hermes-uv-cache-${DRIVE_ID}"
    mkdir -p "$UV_CACHE_DIR"

    # Save updated path
    echo "$VIRTUAL_ENV" > "$RUNTIME_DIR/venv.path"

    rm -rf "$VIRTUAL_ENV"
    if ! "$UV_EXE" venv "$VIRTUAL_ENV" --python "$PYTHON_EXE" --seed 2>/dev/null; then
        "$UV_EXE" venv "$VIRTUAL_ENV" --python "$PYTHON_EXE"
    fi
    if ! "$UV_EXE" pip install --python "$VIRTUAL_ENV/bin/python" --link-mode=copy \
        -e "$SRC_DIR/hermes-agent[all]" \
        "anthropic>=0.39.0" \
        "python-telegram-bot[webhooks]==22.6" 2>/dev/null; then
        "$VIRTUAL_ENV/bin/python" -m ensurepip --upgrade >/dev/null 2>&1 || true
        "$VIRTUAL_ENV/bin/python" -m pip install \
            -e "$SRC_DIR/hermes-agent[all]" \
            "anthropic>=0.39.0" \
            "python-telegram-bot[webhooks]==22.6" 2>/dev/null || true
    fi
    echo "[OK]    Venv rebuilt."
fi

export HERMES_HOME="$HERMES_HOME"
export VIRTUAL_ENV
export PATH="$VIRTUAL_ENV/bin:$RUNTIME_DIR/python/bin:$RUNTIME_DIR/node/bin:$RUNTIME_DIR/uv:$RUNTIME_DIR/bin:$PATH"
export PYTHONNOUSERSITE=1
export PYTHONHOME=""
export PYTHONPATH=""
export UV_NO_CONFIG=1
export UV_PYTHON="$RUNTIME_DIR/python/bin/python3"
export PLAYWRIGHT_BROWSERS_PATH="$RUNTIME_DIR/playwright"
export NODE_PATH="$RUNTIME_DIR/node/lib/node_modules"
export NPM_CONFIG_PREFIX="$RUNTIME_DIR/node"

# Prevent Node/npm from writing to host home directory
export HOME="$PORTABLE_ROOT/.cache/unix-home"
mkdir -p "$HOME"

# ---------------------------------------------------------------------------
# Portable Brain (obsidian-wiki) wiring
# The drive mounts at a different absolute path on every machine, so rewrite
# the vault path here at launch time. Keeps the brain 100% portable.
# ---------------------------------------------------------------------------
BRAIN_VAULT="$PORTABLE_ROOT/Brain"
if [ -d "$BRAIN_VAULT" ]; then
    export OBSIDIAN_VAULT_PATH="$BRAIN_VAULT"
    if [ -f "$BRAIN_VAULT/.env" ]; then
        sed -e "s|^OBSIDIAN_VAULT_PATH=.*|OBSIDIAN_VAULT_PATH=$BRAIN_VAULT|" \
            -e "s|^HERMES_HOME=.*|HERMES_HOME=$HERMES_HOME|" \
            "$BRAIN_VAULT/.env" > "$BRAIN_VAULT/.env.tmp" 2>/dev/null \
            && mv "$BRAIN_VAULT/.env.tmp" "$BRAIN_VAULT/.env"
    fi
    # Global fallback config for the wiki skills' config-resolution protocol.
    mkdir -p "$HOME/.obsidian-wiki"
    {
        echo "OBSIDIAN_VAULT_PATH=$BRAIN_VAULT"
        echo "HERMES_HOME=$HERMES_HOME"
        echo "OBSIDIAN_CATEGORIES=concepts,entities,skills,references,synthesis,journal"
        echo "OBSIDIAN_LINK_FORMAT=wikilink"
    } > "$HOME/.obsidian-wiki/config"
fi

# ---------------------------------------------------------------------------
# Git / GitHub wiring — let Hermes clone/commit/push the owner's repos.
# Token comes from data/.env (GITHUB_TOKEN). Identity + a credential store are
# written into the PORTABLE HOME (.cache/unix-home), never the host's ~/.
# Regenerated each launch so a rotated token just works.
# ---------------------------------------------------------------------------
GITHUB_TOKEN_VAL="$(grep -m1 '^GITHUB_TOKEN=' "$HERMES_HOME/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"'")"
GIT_OK="no"
if command -v git >/dev/null 2>&1; then
    git config --global user.name "Achu Pradeep" 2>/dev/null || true
    git config --global user.email "achupradeep3050@gmail.com" 2>/dev/null || true
    git config --global init.defaultBranch main 2>/dev/null || true
    if [ -n "$GITHUB_TOKEN_VAL" ]; then
        printf 'https://x-access-token:%s@github.com\n' "$GITHUB_TOKEN_VAL" > "$HOME/.git-credentials"
        chmod 600 "$HOME/.git-credentials" 2>/dev/null || true
        git config --global credential.helper store 2>/dev/null || true
        export GITHUB_TOKEN="$GITHUB_TOKEN_VAL"
        export GH_TOKEN="$GITHUB_TOKEN_VAL"
        GIT_OK="yes"
    fi
fi

# ---------------------------------------------------------------------------
# Launch Hermes
# ---------------------------------------------------------------------------
if [ ! -d "$SRC_DIR/hermes-agent" ]; then
    echo "[ERROR] Hermes source not found. Please delete .cache and try again."
    exit 1
fi

cd "$SRC_DIR/hermes-agent"

# Strip "hermes" from the start of arguments if user typed "launch.sh hermes setup"
if [ "$1" = "hermes" ] || [ "$1" = "HERMES" ]; then
    shift
fi

# If explicit arguments were passed, run Hermes directly (skip menu)
if [ $# -gt 0 ]; then
    hermes "$@"
    exit 0
fi

# ---------------------------------------------------------------------------
# ANSI Colors
# ---------------------------------------------------------------------------
ESC='\033'
RESET="${ESC}[0m"
BOLD="${ESC}[1m"
DIM="${ESC}[2m"
CYAN="${ESC}[36m"
BRIGHT_CYAN="${ESC}[96m"
GREEN="${ESC}[32m"
BRIGHT_GREEN="${ESC}[92m"
YELLOW="${ESC}[33m"
BRIGHT_YELLOW="${ESC}[93m"
RED="${ESC}[31m"
BRIGHT_RED="${ESC}[91m"
WHITE="${ESC}[37m"
BRIGHT_WHITE="${ESC}[97m"
GRAY="${ESC}[90m"

# ---------------------------------------------------------------------------
# Status Detection
# ---------------------------------------------------------------------------
detect_status() {
    SETUP_STATUS="Not configured"
    SETUP_ICON="[x]"
    SETUP_COLOR="$RED"
    PROVIDER_NAME=""
    MODEL_NAME=""

    if [ -f "$HERMES_HOME/.env" ] && grep -q '^[A-Z].*=' "$HERMES_HOME/.env"; then
        SETUP_STATUS="Configured"
        SETUP_ICON="[OK]"
        SETUP_COLOR="$BRIGHT_GREEN"
    fi

    if [ -f "$HERMES_HOME/config.yaml" ]; then
        PROVIDER_NAME=$(grep '^  provider:' "$HERMES_HOME/config.yaml" | head -n 1 | awk '{print $2}' || true)
        MODEL_NAME=$(grep '^  default:' "$HERMES_HOME/config.yaml" | head -n 1 | awk '{print $2}' || true)
    fi

    GATEWAY_STATUS="Stopped"
    GATEWAY_ICON="[ ]"
    GATEWAY_COLOR="$GRAY"
    GATEWAY_PID=""

    if [ -f "$HERMES_HOME/gateway.pid" ]; then
        # Hermes writes  "pid": 14029  (WITH a space) — match optional whitespace.
        GATEWAY_PID=$(grep -oE '"pid"[[:space:]]*:[[:space:]]*[0-9]+' "$HERMES_HOME/gateway.pid" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
    fi

    if [ -n "$GATEWAY_PID" ]; then
        if kill -0 "$GATEWAY_PID" 2>/dev/null; then
            GATEWAY_STATUS="Running (PID $GATEWAY_PID)"
            GATEWAY_ICON="[OK]"
            GATEWAY_COLOR="$BRIGHT_GREEN"
        else
            GATEWAY_STATUS="Stopped (stale lock)"
            GATEWAY_ICON="[!]"
            GATEWAY_COLOR="$YELLOW"
        fi
    fi

    HERMES_VERSION="unknown"
    if [ -f "$SRC_DIR/hermes-agent/hermes_cli/__init__.py" ]; then
        HERMES_VERSION=$(grep '__version__' "$SRC_DIR/hermes-agent/hermes_cli/__init__.py" | head -n 1 | sed 's/.*"\(.*\)".*/\1/')
    fi

    # Brain (Obsidian) + connection status
    BRAIN_VAULT="${BRAIN_VAULT:-$PORTABLE_ROOT/Brain}"
    BRAIN_PAGES=0
    if [ -d "$BRAIN_VAULT" ]; then
        BRAIN_PAGES=$(find "$BRAIN_VAULT" -name '*.md' -not -path '*/.obsidian/*' 2>/dev/null | wc -l | tr -d ' ')
    fi
    TELEGRAM_STATUS="Not set"
    grep -qE '^TELEGRAM_BOT_TOKEN=.+' "$HERMES_HOME/.env" 2>/dev/null && TELEGRAM_STATUS="Configured"
    GIT_STATUS="Not set"
    grep -qE '^GITHUB_TOKEN=.+' "$HERMES_HOME/.env" 2>/dev/null && GIT_STATUS="Configured"
}

# ---------------------------------------------------------------------------
# Telegram: ping the owner when the gateway comes online.
# Reads the bot token + chat id straight from data/.env (no extra config).
# This works even if the model has no quota — it's a direct Bot API call.
# ---------------------------------------------------------------------------
gateway_notify() {
    local tok chat
    tok=$(grep -m1 '^TELEGRAM_BOT_TOKEN=' "$HERMES_HOME/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"'" )
    chat=$(grep -m1 '^TELEGRAM_ALLOWED_USERS=' "$HERMES_HOME/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"'" | cut -d, -f1)
    [ -z "$chat" ] && chat=$(grep -m1 '^TELEGRAM_CHAT_ID=' "$HERMES_HOME/.env" 2>/dev/null | cut -d= -f2- | tr -d "\"'")
    if [ -n "$tok" ] && [ -n "$chat" ] && command -v curl >/dev/null 2>&1; then
        curl -s -m 10 "https://api.telegram.org/bot${tok}/sendMessage" \
            -d chat_id="${chat}" \
            --data-urlencode "text=🛸 Hermes gateway is ONLINE${1:+ (PID $1)}. I'm listening on Telegram — send me a message!" \
            >/dev/null 2>&1 &
    fi
}

# ---------------------------------------------------------------------------
# Main Menu
# ---------------------------------------------------------------------------
show_menu() {
    clear
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}${BRIGHT_WHITE}                    HERMES PORTABLE LAUNCHER${RESET}"
    echo -e "${DIM}${GRAY}                         AI Agent for Everyone${RESET}"
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    echo -e " ${DIM}Device${RESET}   ${WHITE}${DEVICE_HOST}${RESET} ${GRAY}·${RESET} ${CYAN}${PRETTY_OS}${RESET}"
    echo -e " ${DIM}Setup${RESET}    ${SETUP_COLOR}${SETUP_ICON}${RESET} ${WHITE}${SETUP_STATUS}${RESET}"
    [ -n "$PROVIDER_NAME" ] && echo -e " ${DIM}Provider${RESET} ${CYAN}${PROVIDER_NAME}${RESET}"
    [ -n "$MODEL_NAME" ] && echo -e " ${DIM}Model${RESET}    ${WHITE}${MODEL_NAME}${RESET}"
    if [ "${BRAIN_PAGES:-0}" -gt 0 ] 2>/dev/null; then
        echo -e " ${DIM}Brain${RESET}    ${BRIGHT_GREEN}[OK]${RESET} ${WHITE}${BRAIN_PAGES} pages${RESET} ${GRAY}(Obsidian vault)${RESET}"
    else
        echo -e " ${DIM}Brain${RESET}    ${GRAY}[ ] not built${RESET}"
    fi
    echo -e " ${DIM}Gateway${RESET}  ${GATEWAY_COLOR}${GATEWAY_ICON}${RESET} ${WHITE}${GATEWAY_STATUS}${RESET}"
    echo -e " ${DIM}Telegram${RESET} ${WHITE}${TELEGRAM_STATUS}${RESET}   ${DIM}Git${RESET} ${WHITE}${GIT_STATUS}${RESET}"
    echo -e " ${DIM}Version${RESET}  ${GRAY}v${HERMES_VERSION}${RESET}"
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    echo -e "  ${BRIGHT_YELLOW}[1]${RESET}  ${WHITE}Start Hermes Chat${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[2]${RESET}  ${WHITE}Setup / Reconfigure Hermes${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[M]${RESET}  ${WHITE}Switch Model / Provider${RESET}  ${GRAY}fast${RESET}"
    if [ "$GATEWAY_STATUS" = "Running (PID $GATEWAY_PID)" ]; then
        echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  ${WHITE}Stop Gateway${RESET}  ${RED}[live]${RESET}"
    else
        echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  ${WHITE}Start Gateway${RESET}"
    fi
    echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  ${WHITE}Advanced Options${RESET}  ${GRAY}-->${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[5]${RESET}  ${WHITE}Eject USB Safely${RESET}  ${GRAY}save · organise · eject${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[6]${RESET}  ${GRAY}Exit${RESET}"
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    read -p "$(echo -e "${BRIGHT_CYAN}Select option: ${RESET}")" choice

    case "$choice" in
        1) menu_chat ;;
        2) menu_setup ;;
        3) menu_gateway ;;
        4) show_advanced ;;
        5) menu_eject ;;
        6) menu_exit ;;
        m|M) menu_model ;;
        e|E) menu_eject ;;
        *) show_menu ;;
    esac
}

menu_chat() {
    clear
    hermes
    show_menu
}

menu_setup() {
    clear
    hermes setup
    detect_status
    show_menu
}

# ---------------------------------------------------------------------------
# Fast model / provider switcher
# ---------------------------------------------------------------------------
_apply_model() {   # provider  model  base_url(""=none)  [ENVKEY=VALUE]
    local p="$1" m="$2" b="$3" e="$4"
    if [ -n "$e" ]; then
        python "$PORTABLE_ROOT/scripts/switch-model.py" --config "$HERMES_HOME/config.yaml" --env "$HERMES_HOME/.env" --provider "$p" --model "$m" --base-url "$b" --set-env "$e"
    else
        python "$PORTABLE_ROOT/scripts/switch-model.py" --config "$HERMES_HOME/config.yaml" --env "$HERMES_HOME/.env" --provider "$p" --model "$m" --base-url "$b"
    fi
}

# Google Gemini via "Login with Google" (OAuth) — no API key.
# Drives hermes-agent's native `google-gemini-cli` provider, which runs a
# browser PKCE sign-in and talks to Google's Cloud Code Assist backend.
# Credentials are written to $HERMES_HOME/auth/google_oauth.json — i.e. they
# live on the USB (data/ is gitignored), so the login travels with the drive.
# Heads-up: Google's policy treats third-party use of the gemini-cli OAuth
# client as a ToS gray-area; Hermes shows its own warning before sign-in.
menu_model_gemini_oauth() {
    echo ""
    echo -e "${BRIGHT_YELLOW}Google Gemini — Login with Google (OAuth, no API key)${RESET}"
    echo -e "${GRAY}A browser window will open so you can sign in to Google. The login is${RESET}"
    echo -e "${GRAY}stored on this USB, so it works on any machine you plug into.${RESET}"
    echo ""
    # Native OAuth login. Creds -> $HERMES_HOME/auth/google_oauth.json.
    hermes auth add google-gemini-cli
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}Google sign-in did not complete (exit $rc) — model left unchanged.${RESET}"
        return 1
    fi
    echo ""
    local m
    read -p "Gemini model [gemini-3-pro-preview]: " m; m=${m:-gemini-3-pro-preview}
    _apply_model "google-gemini-cli" "$m" ""
    echo -e "${BRIGHT_GREEN}Switched to Google Gemini (login) — $m${RESET}"
}

menu_model() {
    clear
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}${BRIGHT_WHITE}                  Switch Model / Provider${RESET}"
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    echo -e "  ${BRIGHT_YELLOW}[1]${RESET}  ${WHITE}Kimi for Coding${RESET}      ${GRAY}cloud (current default)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[2]${RESET}  ${WHITE}Ollama${RESET}               ${GRAY}local LLM server${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  ${WHITE}LM Studio${RESET}            ${GRAY}local LLM server${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  ${WHITE}Google Gemini${RESET}        ${GREEN}login with Google${RESET} ${GRAY}(no API key)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[5]${RESET}  ${WHITE}Google Gemini${RESET}        ${GRAY}cloud (API key)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[6]${RESET}  ${WHITE}OpenRouter${RESET}           ${GRAY}cloud, 300+ models${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[7]${RESET}  ${WHITE}Anthropic Claude${RESET}     ${GRAY}cloud (API key)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[8]${RESET}  ${WHITE}Custom endpoint${RESET}      ${GRAY}any OpenAI-compatible URL${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[9]${RESET}  ${WHITE}Full interactive picker${RESET}  ${GRAY}(hermes model)${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[10]${RESET} ${GRAY}Back${RESET}"
    echo ""
    read -p "$(echo -e "${BRIGHT_CYAN}Select model: ${RESET}")" mc
    case "$mc" in
        1) _apply_model "kimi-coding" "kimi-for-coding" "" ;;
        2) read -p "Ollama model [llama3.1]: " m; m=${m:-llama3.1}
           read -p "Ollama URL [http://localhost:11434/v1]: " u; u=${u:-http://localhost:11434/v1}
           _apply_model "custom" "$m" "$u" "OPENAI_API_KEY=ollama" ;;
        3) read -p "LM Studio model (name shown in LM Studio): " m
           read -p "LM Studio URL [http://127.0.0.1:1234/v1]: " u; u=${u:-http://127.0.0.1:1234/v1}
           _apply_model "lmstudio" "$m" "$u" ;;
        4) menu_model_gemini_oauth ;;
        5) read -p "Gemini model [gemini-2.5-flash]: " m; m=${m:-gemini-2.5-flash}
           read -p "GEMINI_API_KEY: " k
           _apply_model "gemini" "$m" "" "GEMINI_API_KEY=$k" ;;
        6) read -p "OpenRouter model [anthropic/claude-sonnet-4]: " m; m=${m:-anthropic/claude-sonnet-4}
           read -p "OPENROUTER_API_KEY: " k
           _apply_model "openrouter" "$m" "" "OPENROUTER_API_KEY=$k" ;;
        7) read -p "Claude model [claude-sonnet-4-6]: " m; m=${m:-claude-sonnet-4-6}
           read -p "ANTHROPIC_API_KEY: " k
           _apply_model "anthropic" "$m" "" "ANTHROPIC_API_KEY=$k" ;;
        8) read -p "Base URL (OpenAI-compatible): " u
           read -p "Model name: " m
           read -p "API key (blank if none): " k
           if [ -n "$k" ]; then _apply_model "custom" "$m" "$u" "OPENAI_API_KEY=$k"; else _apply_model "custom" "$m" "$u"; fi ;;
        9) hermes model ;;
        10) detect_status; show_menu; return ;;
        *) menu_model; return ;;
    esac
    echo ""
    read -p "Press Enter to continue ..."
    detect_status
    show_menu
}

menu_gateway() {
    if [ "$GATEWAY_STATUS" = "Running (PID $GATEWAY_PID)" ]; then
        hermes gateway stop
        echo ""
        echo -e "${BRIGHT_GREEN}Gateway stopped.${RESET}"
    else
        echo ""
        echo -e "${CYAN}Starting gateway (detached) ...${RESET}"
        # Fully detach so the launcher/terminal is NEVER held by the gateway:
        #   - stdin from /dev/null  (gateway can't grab the TTY)
        #   - stdout/stderr to log  (no console spew)
        #   - nohup + disown        (survives terminal close, off the job table)
        # We use `gateway run` (foreground worker) but background it ourselves —
        # this is portable (no host launchd/systemd pollution) unlike `gateway start`.
        mkdir -p "$HERMES_HOME/logs"
        nohup hermes gateway run > "$HERMES_HOME/logs/gateway.log" 2>&1 < /dev/null &
        disown 2>/dev/null || true
        echo -e "${DIM}Waiting for the gateway to come up ...${RESET}"
        sleep 4
        detect_status
        if [ "$GATEWAY_STATUS" = "Running (PID $GATEWAY_PID)" ]; then
            echo -e "${BRIGHT_GREEN}Gateway started (PID $GATEWAY_PID).${RESET}"
            echo -e "${DIM}Logs: data/logs/gateway.log${RESET}"
            gateway_notify "$GATEWAY_PID"
            echo -e "${CYAN}Sent you a Telegram ping — check @Hermes3050bot.${RESET}"
        else
            echo -e "${YELLOW}Gateway didn't report ready yet — check Advanced > View Logs.${RESET}"
            tail -n 5 "$HERMES_HOME/logs/gateway.log" 2>/dev/null
        fi
    fi
    read -p "Press Enter to continue ..."
    detect_status
    show_menu
}

menu_eject() {
    clear
    # Saves sessions, organises & syncs the Brain, then ejects the USB.
    bash "$PORTABLE_ROOT/scripts/safe-eject.sh"
    rc=$?
    if [ "$rc" -eq 10 ]; then
        # user cancelled at the confirm prompt — back to the menu
        show_menu
        return
    fi
    echo ""
    echo -e "${GRAY}Launcher closed so the drive can be removed. Goodbye!${RESET}"
    echo ""
    exit 0
}

menu_exit() {
    clear
    echo ""
    echo -e "${GRAY}Goodbye!${RESET}"
    echo ""
    exit 0
}

# ---------------------------------------------------------------------------
# Advanced Menu
# ---------------------------------------------------------------------------
show_advanced() {
    clear
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}${BRIGHT_WHITE}                       Advanced Options${RESET}"
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    echo -e "  ${BRIGHT_YELLOW}[1]${RESET}  ${WHITE}Run Doctor${RESET}            ${GRAY}- check for issues${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[2]${RESET}  ${WHITE}View Logs${RESET}             ${GRAY}- last 20 lines${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[3]${RESET}  ${WHITE}Edit Config${RESET}           ${GRAY}- open in editor${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[4]${RESET}  ${WHITE}Restart Gateway${RESET}       ${GRAY}- stop + start${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[5]${RESET}  ${WHITE}Update Hermes${RESET}         ${GRAY}- fetch latest${RESET}"
    echo -e "  ${BRIGHT_YELLOW}[6]${RESET}  ${GRAY}Back to Main Menu${RESET}"
    echo ""
    echo -e "${BRIGHT_CYAN}----------------------------------------------------------------${RESET}"
    echo ""
    read -p "$(echo -e "${BRIGHT_CYAN}Select option: ${RESET}")" choice

    case "$choice" in
        1) adv_doctor ;;
        2) adv_logs ;;
        3) adv_config ;;
        4) adv_restart ;;
        5) adv_update ;;
        6) show_menu ;;
        *) show_advanced ;;
    esac
}

adv_doctor() {
    clear
    hermes doctor
    read -p "Press Enter to continue ..."
    show_advanced
}

adv_logs() {
    clear
    if [ -f "$HERMES_HOME/logs/gateway.log" ]; then
        echo -e "${CYAN}=== Gateway Log (last 20 lines) ===${RESET}"
        tail -n 20 "$HERMES_HOME/logs/gateway.log"
    else
        echo -e "${YELLOW}No logs found.${RESET}"
    fi
    echo ""
    read -p "Press Enter to continue ..."
    show_advanced
}

adv_config() {
    clear
    hermes config edit
    show_advanced
}

adv_restart() {
    echo -e "${CYAN}Restarting gateway (detached) ...${RESET}"
    hermes gateway stop 2>/dev/null || true
    sleep 1
    mkdir -p "$HERMES_HOME/logs"
    nohup hermes gateway run > "$HERMES_HOME/logs/gateway.log" 2>&1 < /dev/null &
    disown 2>/dev/null || true
    sleep 4
    detect_status
    if [ "$GATEWAY_STATUS" = "Running (PID $GATEWAY_PID)" ]; then
        echo -e "${BRIGHT_GREEN}Gateway restarted (PID $GATEWAY_PID).${RESET}"
        gateway_notify "$GATEWAY_PID"
    else
        echo -e "${YELLOW}Gateway didn't report ready — check Advanced > View Logs.${RESET}"
    fi
    read -p "Press Enter to continue ..."
    detect_status
    show_menu
}

adv_update() {
    clear
    hermes update
    read -p "Press Enter to continue ..."
    show_advanced
}

# ---------------------------------------------------------------------------
# Device memory — record THIS machine (and what works on it) into the brain,
# so the Obsidian vault remembers every device the drive has run on.
# ---------------------------------------------------------------------------
record_device() {
    [ -d "$BRAIN_VAULT" ] || return 0
    local dir="$BRAIN_VAULT/devices"
    mkdir -p "$dir" 2>/dev/null || return 0
    local now first f rt
    now="$(date '+%Y-%m-%d %H:%M' 2>/dev/null || echo unknown)"
    f="$dir/${DEVICE_SLUG}.md"
    first="$now"
    if [ -f "$f" ]; then
        first="$(grep -m1 '^first_seen:' "$f" 2>/dev/null | sed 's/^first_seen:[[:space:]]*//')"
        [ -z "$first" ] && first="$now"
    fi
    rt="missing"; [ -f "$RUNTIME_DIR/ready.flag" ] && rt="ready"
    cat > "$f" <<EOF
---
title: Device — ${DEVICE_HOST} (${PRETTY_OS})
category: devices
tags: [device, ${PLATFORM}, ${ARCH}]
first_seen: ${first}
last_seen: ${now}
---

# ${DEVICE_HOST} — ${PRETTY_OS}

- **Platform:** ${PRETTY_OS}  (\`${PLATFORM}-${ARCH}\`)
- **Runtime:** ${rt}  (\`.cache/runtimes/${PLATFORM}-${ARCH}\`)
- **Model last used:** ${MODEL_NAME:-unset} (${PROVIDER_NAME:-?})
- **Setup:** ${SETUP_STATUS}
- **Gateway (last seen):** ${GATEWAY_STATUS}
- **Telegram:** ${TELEGRAM_STATUS}  ·  **Git:** ${GIT_STATUS}
- **Brain pages:** ${BRAIN_PAGES}
- **First seen:** ${first}  ·  **Last seen:** ${now}

*Auto-updated by launch.sh every time the drive runs on this machine.*
EOF
    if [ ! -f "$dir/_log.md" ]; then
        printf '# Device Run Log\n\nEvery launch of this drive, on every machine.\n\n' > "$dir/_log.md"
    fi
    echo "- [${now}] ${DEVICE_HOST} · ${PRETTY_OS} · model=${MODEL_NAME:-unset} · gateway=${GATEWAY_STATUS} · runtime=${rt}" >> "$dir/_log.md"
}

# ---------------------------------------------------------------------------
# Startup splash — shows where we are, what loaded, brain optimized, etc.
# ---------------------------------------------------------------------------
startup_banner() {
    clear
    echo ""
    echo -e "${BRIGHT_CYAN}================================================================${RESET}"
    echo -e "${BOLD}${BRIGHT_WHITE}            HERMES PORTABLE  —  starting up${RESET}"
    echo -e "${BRIGHT_CYAN}================================================================${RESET}"
    echo ""
    echo -e "  ${BRIGHT_GREEN}OK${RESET}  Running on ${CYAN}${PRETTY_OS}${RESET} as ${WHITE}${DEVICE_HOST}${RESET}"
    echo -e "  ${BRIGHT_GREEN}OK${RESET}  Portable runtime loaded ${GRAY}(.cache/runtimes/${PLATFORM}-${ARCH})${RESET}"
    echo -e "  ${BRIGHT_GREEN}OK${RESET}  Model ${WHITE}${MODEL_NAME:-unset}${RESET} via ${CYAN}${PROVIDER_NAME:-?}${RESET}"
    if [ "${BRAIN_PAGES:-0}" -gt 0 ] 2>/dev/null; then
        echo -e "  ${BRIGHT_GREEN}OK${RESET}  Obsidian brain optimized & ready ${WHITE}(${BRAIN_PAGES} pages)${RESET} ${GRAY}-> Brain/${RESET}"
    else
        echo -e "  ${YELLOW}!!${RESET}  Obsidian brain not found at Brain/"
    fi
    echo -e "  ${BRIGHT_GREEN}OK${RESET}  Telegram ${WHITE}${TELEGRAM_STATUS}${RESET}  ${GRAY}|${RESET}  Git ${WHITE}${GIT_STATUS}${RESET}"
    echo -e "  ${BRIGHT_GREEN}OK${RESET}  This device remembered ${GRAY}(Brain/devices/${DEVICE_SLUG}.md)${RESET}"
    echo ""
    echo -e "  ${DIM}Opening dashboard ...${RESET}"
    sleep 2
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
detect_status
record_device
startup_banner
show_menu
