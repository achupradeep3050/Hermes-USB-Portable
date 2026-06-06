# ============================================================================
# Hermes Portable - Device note writer (Windows)
# ============================================================================
# Writes / refreshes this machine's device note in the brain
# (Brain\devices\<slug>.md) and appends Brain\devices\_log.md.
#
# Called by launch.bat's :record_device subroutine. Kept as a separate script
# (not inline in the .bat) so the rich content + parentheses in values like
# "Windows 10 (x64)" can't break cmd's batch parser, and so the note matches
# the richer format launch.sh writes on macOS.
#
# Windows-only and additive: does NOT touch launch.sh / the macOS path.
# ============================================================================

param(
    [Parameter(Mandatory = $true)] [string]$Root,
    [Parameter(Mandatory = $true)] [string]$DeviceSlug,
    [Parameter(Mandatory = $true)] [string]$DeviceHost,
    [Parameter(Mandatory = $true)] [string]$PrettyOS
)

$ErrorActionPreference = "SilentlyContinue"

$brain   = Join-Path $Root "Brain"
$dataDir = Join-Path $Root "data"
$devDir  = Join-Path $brain "devices"
New-Item -ItemType Directory -Force -Path $devDir | Out-Null

$now  = Get-Date -Format "yyyy-MM-dd HH:mm"
$note = Join-Path $devDir ($DeviceSlug + ".md")

# Preserve first_seen across runs
$first = $now
if (Test-Path $note) {
    $mm = Select-String -Path $note -Pattern '^first_seen:'
    if ($mm) { $first = ($mm.Line -replace '^first_seen:\s*', '') }
}

# --- Provider + model from config.yaml (strip surrounding quotes) -----------
$provider = "unknown"
$model    = "unknown"
$cfg = Join-Path $dataDir "config.yaml"
if (Test-Path $cfg) {
    $cfgLines = Get-Content $cfg
    $pm = $cfgLines | Select-String -Pattern '^\s*provider:\s*(.+)$' | Select-Object -First 1
    if ($pm) { $provider = ($pm.Matches[0].Groups[1].Value.Trim() -replace '^"|"$', '') }
    $mm = $cfgLines | Select-String -Pattern '^\s*default:\s*(.+)$' | Select-Object -First 1
    if ($mm) { $model = ($mm.Matches[0].Groups[1].Value.Trim() -replace '^"|"$', '') }
}

# --- Telegram / Git wiring presence from .env ------------------------------
$telegram = "Not set"
$git      = "Not set"
$envFile  = Join-Path $dataDir ".env"
if (Test-Path $envFile) {
    $envLines = Get-Content $envFile
    if ($envLines | Select-String -Pattern '^TELEGRAM_BOT_TOKEN=.') { $telegram = "Configured" }
    if ($envLines | Select-String -Pattern '^GITHUB_TOKEN=.')       { $git = "Configured" }
}

# --- Brain page count ------------------------------------------------------
$pages = (Get-ChildItem $brain -Recurse -Filter *.md -Force | Measure-Object).Count

# --- Runtime readiness -----------------------------------------------------
$runtime = "not ready"
if (Test-Path (Join-Path $Root ".cache\runtimes\windows-x64\venv\Scripts\hermes.exe")) {
    $runtime = "ready"
}

$lines = @(
    '---',
    ("title: Device - $DeviceHost ($PrettyOS)"),
    'category: devices',
    'tags: [device, windows, x64]',
    ("first_seen: $first"),
    ("last_seen: $now"),
    '---',
    '',
    ("# $DeviceHost - $PrettyOS"),
    '',
    ("- **Platform:** $PrettyOS  (``windows-x64``)"),
    ("- **Runtime:** $runtime  (``.cache/runtimes/windows-x64``)"),
    ("- **Provider:** $provider"),
    ("- **Model last used:** $model"),
    ("- **Setup:** Configured"),
    ("- **Telegram:** $telegram  |  **Git:** $git"),
    ("- **Brain pages:** $pages"),
    ("- **First seen:** $first  |  **Last seen:** $now"),
    '',
    '*Auto-updated by launch.bat every time the drive runs on this machine.*'
)
Set-Content -Path $note -Value $lines -Encoding utf8

# Append run log
$log = Join-Path $devDir "_log.md"
if (-not (Test-Path $log)) { Set-Content $log '# Device Run Log' -Encoding utf8 }
Add-Content $log ("- [$now] $DeviceHost - $PrettyOS  |  $provider / $model") -Encoding utf8
