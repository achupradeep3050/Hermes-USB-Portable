# Portable Chrome Launcher

Carry your Chrome profile (logins, bookmarks, extensions) on the USB drive so you never need to re-login on a new PC.

## Quick Start

1. **Import your current profile** (one-time):
   ```
   chrome-launcher\launch-chrome.py --import
   ```

2. **Launch Chrome** from anywhere:
   ```
   chrome-launcher\launch-chrome.py [URL]
   ```
   Or just double-click `chrome-launcher\chrome.bat`

## What it does

- Uses the host PC's Chrome executable (already installed on most PCs)
- Loads your profile from `chrome-profile/User Data/Default` on this USB
- Saves downloads to `chrome-downloads/` on this USB
- Excludes large transient caches (GPUCache, Code Cache, Service Worker cache) to keep ~400MB smaller

## Moving to a new PC

1. Plug in the USB
2. Run `chrome-launcher\chrome.bat`
3. Your YouTube Premium, Google Account, bookmarks — everything is already logged in

## Updating the profile

If you update bookmarks/extensions on a host PC and want to sync back:
```
python chrome-launcher\launch-chrome.py --import --force
```
This copies all new profile data from the current PC. You'll need to close Chrome first.
