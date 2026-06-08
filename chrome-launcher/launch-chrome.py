#!/usr/bin/env python3
"""
Portable Chrome Launcher for Hermes USB

Launches the host system's Chrome with a profile stored on the USB drive.
This allows you to carry your Chrome login sessions (YouTube Premium, etc.)
across PCs without re-logging in. Downloads go to a USB folder too.

Usage:
    python launch-chrome.py [URL]
    python launch-chrome.py --import   # copy current host profile to USB
"""
import os
import sys
import shutil
import subprocess
import json
import argparse
from pathlib import Path


def get_usb_root() -> Path:
    """Find the USB root from the HERMES_HOME env var or script location."""
    if 'HERMES_HOME' in os.environ:
        data = Path(os.environ['HERMES_HOME'])
        return data.parent
    script = Path(__file__).resolve()
    return script.parent.parent


def get_host_chrome() -> str:
    """Find the host system's Chrome executable."""
    candidates = [
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    raise FileNotFoundError("Google Chrome not found on this PC. Install it or use a Chromium portable build.")


def get_host_default_profile() -> Path:
    """Find the host's Chrome Default profile directory.
    NOTE: In the Hermes portable env LOCALAPPDATA is redirected, so we use the real host path."""
    userprofile = os.environ.get('USERPROFILE', r'C:\Users')  # real Windows profile
    localappdata = Path(userprofile) / 'AppData' / 'Local'
    path = localappdata / 'Google' / 'Chrome' / 'User Data' / 'Default'
    if path.exists():
        return path
    raise FileNotFoundError(f"Cannot find host Chrome profile at {path}")


def get_usb_profile(usb_root: Path) -> Path:
    """Return the USB profile directory (creates skeleton if empty)."""
    profile = usb_root / 'chrome-profile' / 'User Data' / 'Default'
    if not profile.exists():
        profile.mkdir(parents=True, exist_ok=True)
    return profile


def set_download_dir(usb_root: Path, profile_dir: Path):
    """Injects the USB download path into Chrome Preferences."""
    pref_file = profile_dir / 'Preferences'
    downloads_dir = str(usb_root / 'chrome-downloads').replace('\\', '\\')

    if not pref_file.exists():
        pref_file.write_text('{}', encoding='utf-8')

    try:
        data = json.loads(pref_file.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        data = {}

    data.setdefault('download', {})
    data['download']['default_directory'] = downloads_dir

    # Also set save-as directory
    data.setdefault('savefile', {})
    data['savefile']['default_directory'] = downloads_dir

    pref_file.write_text(json.dumps(data, indent=2), encoding='utf-8')


def import_host_profile(usb_root: Path, force: bool = False):
    """Copy the host's Default Chrome profile to the USB."""
    usb_profile = get_usb_profile(usb_root)
    host_profile = get_host_default_profile()

    if usb_profile.exists() and any(usb_profile.iterdir()) and not force:
        print(f"USB profile already exists at {usb_profile}")
        print("Use --force to overwrite.")
        return

    if usb_profile.exists() and force:
        print(f"Removing old USB profile...")
        shutil.rmtree(usb_profile.parent)
        usb_profile.mkdir(parents=True, exist_ok=True)

    print(f"Copying host profile from {host_profile}")
    print(f"  -> to {usb_profile}")

    # Exclude massive transient caches to keep USB profile lean
    skip = {
        'Cache', 'Code Cache', 'GPUCache', 'Service Worker', 'Storage', 'optimization_guide',
        'File System', 'blob_storage', 'Network', 'Session Storage', 'SharedStorage',
        'IndexedDB', 'WebStorage', 'GrShaderCache', 'GraphiteDawnCache',
    }
    copied = 0
    skipped = 0
    for item in host_profile.iterdir():
        if item.name in skip:
            skipped += 1
            continue
        dest = usb_profile / item.name
        try:
            if item.is_dir():
                shutil.copytree(item, dest, dirs_exist_ok=True)
            else:
                shutil.copy2(item, dest)
            copied += 1
        except PermissionError:
            # Skip locked SQLite databases
            skipped += 1
    print(f"Done. Copied {copied} items, skipped {skipped} (running Chrome locks some files).")
    print("If skipped too many critical files (Login Data, Cookies), close Chrome and rerun.")


def launch_chrome(usb_root: Path, url: str = None):
    """Launch Chrome with the portable profile."""
    chrome = get_host_chrome()
    usb_profile = get_usb_profile(usb_root)
    user_data_dir = usb_root / 'chrome-profile' / 'User Data'

    if not any(usb_profile.iterdir()):
        print("USB Chrome profile is empty. Run with --import to copy from this PC first.")
        sys.exit(1)

    set_download_dir(usb_root, usb_profile)

    cmd = [
        chrome,
        f'--user-data-dir={user_data_dir}',
        '--no-first-run',
        '--no-default-browser-check',
    ]
    if url:
        cmd.append(url)
    else:
        cmd.append('about:blank')

    localappdata = os.environ.get('LOCALAPPDATA', '')
    env = os.environ.copy()
    env['LOCALAPPDATA'] = localappdata

    print(f"Launching Chrome...")
    print(f"  Exe:   {chrome}")
    print(f"  Profile: {user_data_dir}")
    print(f"  Downloads: {usb_root / 'chrome-downloads'}")
    if url:
        print(f"  URL:   {url}")

    subprocess.Popen(cmd, env=env)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Portable Chrome Launcher')
    parser.add_argument('url', nargs='?', default=None, help='URL to open (optional)')
    parser.add_argument('--import', dest='import_profile', action='store_true',
                        help='Import current host profile to USB')
    parser.add_argument('--force', action='store_true',
                        help='Force overwrite when importing')
    args = parser.parse_args()

    usb = get_usb_root()

    if args.import_profile:
        import_host_profile(usb, force=args.force)
    else:
        launch_chrome(usb, url=args.url)
