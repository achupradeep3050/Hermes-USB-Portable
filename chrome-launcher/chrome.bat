@echo off
REM Portable Chrome Launcher — double-click to run
setlocal
set SCRIPT_DIR=%~dp0
set USB_ROOT=%SCRIPT_DIR%..\
cd /d "%USB_ROOT%"

if "%~1"=="" (
    python "chrome-launcher\launch-chrome.py"
) else (
    python "chrome-launcher\launch-chrome.py" %*
)
