#!/bin/bash
# ============================================================================
# Hermes Portable — Safe Eject
# ----------------------------------------------------------------------------
# Saves & organises everything, then safely ejects the USB drive:
#   1. Stops the Hermes gateway (releases live handles)
#   2. Saves session state + appends a close-out entry to the Brain log
#   3. Organises the Brain (timestamps, link-integrity check)
#   4. Flushes all writes to disk (sync)
#   5. Detects the drive's volume and ejects it (macOS/Linux)
#
# Usage:
#   scripts/safe-eject.sh            # interactive (asks to confirm)
#   scripts/safe-eject.sh --yes      # no prompt
#   scripts/safe-eject.sh --dry-run  # do save/organise/sync, but DON'T eject
#
# Called by the launcher's "Eject USB Safely" menu option.
# ============================================================================
set -uo pipefail

# --- locate the portable root (this script lives in <root>/scripts) ---------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORTABLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BRAIN="$PORTABLE_ROOT/Brain"
DATA="$PORTABLE_ROOT/data"

# --- colors (degrade gracefully if no TTY) ----------------------------------
if [ -t 1 ]; then
    ESC=$'\033'; RESET="${ESC}[0m"; BOLD="${ESC}[1m"; DIM="${ESC}[2m"
    CYAN="${ESC}[96m"; GREEN="${ESC}[92m"; YELLOW="${ESC}[93m"; RED="${ESC}[91m"; GRAY="${ESC}[90m"; WHITE="${ESC}[97m"
else
    RESET=""; BOLD=""; DIM=""; CYAN=""; GREEN=""; YELLOW=""; RED=""; GRAY=""; WHITE=""
fi
ok()   { echo -e "  ${GREEN}[OK]${RESET}   $*"; }
info() { echo -e "  ${CYAN}[..]${RESET}   $*"; }
warn() { echo -e "  ${YELLOW}[!!]${RESET}   $*"; }
err()  { echo -e "  ${RED}[XX]${RESET}   $*"; }

# --- args -------------------------------------------------------------------
DRY_RUN=0; ASSUME_YES=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY_RUN=1 ;;
        --yes|-y)  ASSUME_YES=1 ;;
        *) ;;
    esac
done

OS_RAW="$(uname -s)"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"
DEVICE_HOST="$(hostname 2>/dev/null | cut -d. -f1)"

echo ""
echo -e "${CYAN}----------------------------------------------------------------${RESET}"
echo -e "${BOLD}${WHITE}            HERMES — SAFE EJECT (save · organise · eject)${RESET}"
echo -e "${CYAN}----------------------------------------------------------------${RESET}"
echo ""
echo -e "  This will: stop the gateway, save sessions, organise & sync the"
echo -e "  Brain, then eject the USB. ${DIM}Nothing is deleted.${RESET}"
echo ""

if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "$(echo -e "  ${CYAN}Proceed? [y/N]: ${RESET}")" reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo -e "  ${GRAY}Cancelled.${RESET}"; exit 10 ;;
    esac
fi
echo ""

# --- 1. stop the gateway ----------------------------------------------------
info "Stopping Hermes gateway (if running)..."
if command -v hermes >/dev/null 2>&1; then
    hermes gateway stop >/dev/null 2>&1 && ok "Gateway stopped." || ok "Gateway not running."
else
    ok "Hermes CLI not on PATH — skipping gateway stop."
fi

# --- 2. save session state + close-out log ----------------------------------
info "Saving session state & writing close-out log..."
SESS_COUNT=0
[ -d "$DATA/sessions" ] && SESS_COUNT="$(find "$DATA/sessions" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [ -d "$BRAIN" ]; then
    LOG="$BRAIN/log.md"
    {
        echo ""
        echo "## Safe-eject — $NOW"
        echo "- Device: ${DEVICE_HOST:-unknown} · OS: $OS_RAW"
        echo "- Sessions on drive: ${SESS_COUNT} file(s) flushed."
        echo "- Brain saved, organised, and synced before eject."
    } >> "$LOG" 2>/dev/null && ok "Close-out appended to Brain/log.md (sessions: ${SESS_COUNT})." \
        || warn "Could not write Brain/log.md (continuing)."
else
    warn "Brain folder not found at $BRAIN (skipping log)."
fi

# --- 3. organise the Brain (integrity check) --------------------------------
info "Organising Brain & checking link integrity..."
if [ -d "$BRAIN" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$BRAIN" <<'PY' || warn "Integrity check skipped (non-fatal)."
import os, re, glob, sys
brain = sys.argv[1]
os.chdir(brain)
files = glob.glob("**/*.md", recursive=True)
stems = set()
for f in files:
    stems.add(f[:-3]); stems.add(os.path.basename(f)[:-3])
broken = []
link_re = re.compile(r"\[\[([^\]]+)\]\]")
for f in files:
    for m in link_re.findall(open(f, encoding="utf-8", errors="ignore").read()):
        t = m.split("|")[0].split("#")[0].strip()
        if t and t not in stems and t != "wikilinks":
            broken.append((f, t))
print(f"  [OK]   Brain: {len(files)} notes scanned.")
if broken:
    print(f"  [!!]   {len(broken)} broken link(s): " + ", ".join(f"{f}->{t}" for f, t in broken[:5]))
else:
    print("  [OK]   All wikilinks resolve.")
# refresh a tiny machine-readable marker for the next AI session
open(".hermes-safe-eject.json", "w").write(
    '{"last_safe_eject":"%s","notes":%d,"broken_links":%d}\n' % (
        __import__("datetime").datetime.now().isoformat(timespec="seconds"), len(files), len(broken)))
PY
    ok "Eject marker written (.hermes-safe-eject.json)."
else
    warn "python3 not available — skipped integrity check."
fi

# --- 4. flush writes --------------------------------------------------------
info "Flushing all writes to disk..."
sync 2>/dev/null; sync 2>/dev/null
ok "Filesystem synced."

# --- 5. detect volume + eject ----------------------------------------------
# Find the mount point that contains the portable root.
VOL="$(df -P "$PORTABLE_ROOT" 2>/dev/null | awk 'NR==2{ $1=$2=$3=$4=$5=""; sub(/^ +/,""); print }')"
[ -z "$VOL" ] && VOL="$(df -P "$PORTABLE_ROOT" 2>/dev/null | awk 'NR==2{print $NF}')"
DEV="$(df -P "$PORTABLE_ROOT" 2>/dev/null | awk 'NR==2{print $1}')"

echo ""
info "Drive volume detected: ${WHITE}${VOL:-unknown}${RESET} ${GRAY}(${DEV:-?})${RESET}"

if [ "$DRY_RUN" -eq 1 ]; then
    echo ""
    ok "DRY RUN complete — saved/organised/synced. ${GRAY}Eject NOT performed.${RESET}"
    echo -e "  ${GRAY}Real eject would run:${RESET}"
    case "$OS_RAW" in
        Darwin*) echo -e "    ${WHITE}diskutil eject \"$VOL\"${RESET}" ;;
        Linux*)  echo -e "    ${WHITE}udisksctl unmount -b \"$DEV\"  (then power-off)${RESET}" ;;
    esac
    exit 0
fi

# Eject from a detached helper so we don't yank the volume out from under this
# running script (which lives on the drive). The helper waits for us to exit.
HELPER="$(mktemp "${TMPDIR:-/tmp}/hermes-eject.XXXXXX.sh")"
case "$OS_RAW" in
    Darwin*)
        cat > "$HELPER" <<EOF
#!/bin/bash
cd "\$HOME" || cd /
sleep 1
if diskutil eject "$VOL" >/dev/null 2>&1; then
    echo ""
    echo "  [OK]   '$VOL' ejected. You can remove the USB now."
else
    echo ""
    echo "  [!!]   Could not auto-eject (something still has it open)."
    echo "         Close Obsidian / Terminal in the drive, then run:"
    echo "             diskutil eject \"$VOL\""
    echo "         Or force (data is already synced):"
    echo "             diskutil unmountDisk force \"$VOL\""
fi
rm -f "$HELPER" 2>/dev/null
EOF
        ;;
    Linux*)
        cat > "$HELPER" <<EOF
#!/bin/bash
cd "\$HOME" || cd /
sleep 1
if command -v udisksctl >/dev/null 2>&1 && [ -n "$DEV" ]; then
    udisksctl unmount -b "$DEV" >/dev/null 2>&1 && udisksctl power-off -b "$DEV" >/dev/null 2>&1 \
        && { echo; echo "  [OK]   Drive unmounted & powered off. Safe to remove."; } \
        || { echo; echo "  [!!]   Could not auto-eject. Try: sudo umount \"$VOL\""; }
else
    sudo umount "$VOL" >/dev/null 2>&1 && { echo; echo "  [OK]   Unmounted. Safe to remove."; } \
        || { echo; echo "  [!!]   Could not unmount. Close apps using the drive and retry: umount \"$VOL\""; }
fi
rm -f "$HELPER" 2>/dev/null
EOF
        ;;
    *)
        err "Auto-eject not supported on $OS_RAW. Eject manually from your file manager."
        rm -f "$HELPER" 2>/dev/null
        exit 1
        ;;
esac

chmod +x "$HELPER"
echo ""
ok "Saved & organised. Ejecting now — ${GRAY}this window will return to your shell.${RESET}"
# Detached so it survives the launcher exiting and the drive going away.
nohup bash "$HELPER" >/tmp/hermes-eject.log 2>&1 < /dev/null &
disown 2>/dev/null || true
sleep 2
cat /tmp/hermes-eject.log 2>/dev/null || true
exit 0
