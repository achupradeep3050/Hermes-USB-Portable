@echo off & setlocal enabledelayedexpansion

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "HERMES_HOME=%ROOT%\data"
set "RUNTIME_DIR=%ROOT%\.cache\runtimes\windows-x64"
set "VENV_DIR=%RUNTIME_DIR%\venv"
set "HERMES_EXE=%VENV_DIR%\Scripts\hermes.exe"
set "VENV_PY=%VENV_DIR%\Scripts\python.exe"
set "UV_EXE=%RUNTIME_DIR%\uv\uv.exe"
set "PW_DIR=%RUNTIME_DIR%\playwright"
set "APPDATA=%ROOT%\.cache\windows-appdata"
set "LOCALAPPDATA=%ROOT%\.cache\windows-localappdata"
set "HOME=%ROOT%\.cache\windows-home"
set "UV_CACHE_DIR=%ROOT%\.cache\uv-cache"
set "PIP_CACHE_DIR=%ROOT%\.cache\pip-cache"
set "PATH=%VENV_DIR%\Scripts;%RUNTIME_DIR%\python;%RUNTIME_DIR%\python\Scripts;%RUNTIME_DIR%\node;%RUNTIME_DIR%\git\cmd;%RUNTIME_DIR%\uv;%RUNTIME_DIR%\bin;%PATH%"
set "PYTHONNOUSERSITE=1"
set "PYTHONHOME="
set "PYTHONPATH="
set "UV_NO_CONFIG=1"
set "UV_PYTHON=%RUNTIME_DIR%\python\python.exe"
set "PLAYWRIGHT_BROWSERS_PATH=%PW_DIR%"
set "NODE_PATH=%RUNTIME_DIR%\node\node_modules"
set "NPM_CONFIG_PREFIX=%RUNTIME_DIR%\node"
for %%d in ("%APPDATA%" "%LOCALAPPDATA%" "%HOME%" "%UV_CACHE_DIR%" "%PIP_CACHE_DIR%") do if not exist "%%~d" mkdir "%%~d" 2>nul
if exist "%ROOT%\Brain" set "OBSIDIAN_VAULT_PATH=%ROOT%\Brain"

if "%~1"=="" goto :CHAT
if /I "%~1"=="-?" goto :USAGE
if /I "%~1"=="-h" goto :USAGE
if /I "%~1"=="-help" goto :USAGE
if /I "%~1"=="--help" goto :USAGE
if /I "%~1"=="/?" goto :USAGE
if /I "%~1"=="--?" goto :USAGE
if /I "%~1"=="help" goto :USAGE
if /I "%~1"=="start" if "%~2"=="" goto :START
if /I "%~1"=="update" goto :UPDATE
if /I "%~1"=="install" goto :INSTALL
if /I "%~1"=="launcher" goto :LAUNCHER
goto :RUN


:LAUNCHER
if not exist "%ROOT%\launch.bat" goto :NOLAUNCHER
call "%ROOT%\launch.bat"
exit /b 0

:CHAT
if not exist "%HERMES_EXE%" goto :NORUNTIME
"%HERMES_EXE%" --yolo -c --no-restore-cwd --in "%CD%"
exit /b %ERRORLEVEL%

:RUN
if not exist "%HERMES_EXE%" goto :NORUNTIME
cd /d "%ROOT%\src\hermes-agent"
"%HERMES_EXE%" %*
exit /b %ERRORLEVEL%

:START
if not exist "%HERMES_EXE%" goto :NORUNTIME
cd /d "%ROOT%\src\hermes-agent"
"%HERMES_EXE%" gateway run
exit /b %ERRORLEVEL%

:UPDATE
if not exist "%HERMES_EXE%" goto :NORUNTIME
if not "%~3"=="" goto :RUN
if /I "%~2"=="--check" goto :CHECK
if not "%~2"=="" if /I not "%~2"=="/force" if /I not "%~2"=="--force" goto :RUN
set "PIN="
for /f "usebackq tokens=2 delims=:" %%r in (`findstr /b /c:"hermes_agent_ref:" "%ROOT%\VERSION"`) do for /f "tokens=1" %%s in ("%%r") do set "PIN=%%s"
set "INST="
if exist "%ROOT%\src\hermes-agent\.portable-ref" for /f "usebackq delims=" %%s in ("%ROOT%\src\hermes-agent\.portable-ref") do set "INST=%%s"
if not defined PIN echo [ERROR] hermes_agent_ref missing in VERSION & exit /b 1
echo Pin in VERSION:  !PIN!
echo Installed:       !INST!
if "%~2"=="" if /I "!PIN!"=="!INST!" goto :UPTODATE
call :SETUP_RUNTIME
if errorlevel 1 exit /b 1
call :PM
call :PW
echo.
cd /d "%ROOT%\src\hermes-agent"
"%HERMES_EXE%" --version
exit /b 0

:CHECK
set "PIN="
for /f "usebackq tokens=2 delims=:" %%r in (`findstr /b /c:"hermes_agent_ref:" "%ROOT%\VERSION"`) do for /f "tokens=1" %%s in ("%%r") do set "PIN=%%s"
set "INST="
if exist "%ROOT%\src\hermes-agent\.portable-ref" for /f "usebackq delims=" %%s in ("%ROOT%\src\hermes-agent\.portable-ref") do set "INST=%%s"
set "REMOTE_PIN="
set "REMOTE_NOTE="
if not exist "%ROOT%\.git" goto :CHECK_REPORT
pushd "%ROOT%"
set "BRANCH="
for /f "usebackq tokens=*" %%b in (`git rev-parse --abbrev-ref HEAD 2^>nul`) do set "BRANCH=%%b"
if not defined BRANCH goto :CHECK_POP
git fetch --quiet origin "!BRANCH!" >nul 2>&1
if errorlevel 1 set "REMOTE_NOTE= - origin not reachable"
set "VF=%TEMP%\hermes-check-!RANDOM!.txt"
git show "origin/!BRANCH!:VERSION" > "!VF!" 2>nul
for /f "usebackq tokens=2 delims=:" %%r in (`findstr /b /c:"hermes_agent_ref:" "!VF!"`) do for /f "tokens=1" %%s in ("%%r") do set "REMOTE_PIN=%%s"
del "!VF!" >nul 2>&1
:CHECK_POP
popd

:CHECK_REPORT
echo Installed:         !INST!
echo Pin in VERSION:    !PIN!
if defined REMOTE_PIN (echo Pin on origin:     !REMOTE_PIN!) else (echo Pin on origin:     unknown!REMOTE_NOTE!)
set "CHECK_RC=0"
if /I not "!PIN!"=="!INST!" set "CHECK_RC=1"
if defined REMOTE_PIN if /I not "!PIN!"=="!REMOTE_PIN!" set "CHECK_RC=1"
if "!CHECK_RC!"=="1" goto :CHECK_DIFF
echo.
echo [OK] Up to date - installed release, pin and origin agree.
exit /b 0

:CHECK_DIFF
echo.
echo [UPDATE] Update available.
if /I not "!PIN!"=="!INST!" echo     Installed release differs from the pin: hermes update
if defined REMOTE_PIN if /I not "!PIN!"=="!REMOTE_PIN!" echo     Origin has a newer pin: git -C "%ROOT%" pull, then hermes update
exit /b 1

:UPTODATE
echo.
echo [OK] Already up to date - the pinned release is installed.
cd /d "%ROOT%\src\hermes-agent"
"%HERMES_EXE%" --version
exit /b 0

:INSTALL
if not exist "%ROOT%\scripts\setup-windows.ps1" goto :NOINSTALL
call :SETUP_RUNTIME
if errorlevel 1 exit /b 1
call :PM
call :PW
echo.
cd /d "%ROOT%\src\hermes-agent"
"%HERMES_EXE%" setup
exit /b %ERRORLEVEL%

:SETUP_RUNTIME
call :LOCKPROBE
if defined LOCKED (
    echo [WARN] The runtime is in use - stopping the gateway to free it ...
    "%HERMES_EXE%" gateway stop
    ping -n 4 127.0.0.1 >nul
    call :LOCKPROBE
    if defined LOCKED goto :LOCKFAIL
    set "GWRESTART=1"
)
echo.
echo --- Setup: downloading the pinned release, rebuilding the venv ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\setup-windows.ps1" -Root "%ROOT%"
set "SETUP_RC=%ERRORLEVEL%"
if defined GWRESTART "%HERMES_EXE%" gateway start
if not "%SETUP_RC%"=="0" exit /b 1
if not exist "%HERMES_EXE%" exit /b 1
exit /b 0

:LOCKPROBE
set "LOCKED="
if exist "%RUNTIME_DIR%\python" (
    ren "%RUNTIME_DIR%\python" "python._locktest" >nul 2>&1
    if errorlevel 1 (set "LOCKED=1") else (ren "%RUNTIME_DIR%\python._locktest" "python" >nul 2>&1)
)
if defined LOCKED goto :eof
if exist "%RUNTIME_DIR%\venv" (
    ren "%RUNTIME_DIR%\venv" "venv._locktest" >nul 2>&1
    if errorlevel 1 (set "LOCKED=1") else (ren "%RUNTIME_DIR%\venv._locktest" "venv" >nul 2>&1)
)
goto :eof

:PM
echo.
echo --- Portable standard tools ---
"%HERMES_EXE%" pm install
"%HERMES_EXE%" pm install git
set "BASH="
for /d %%g in ("%HERMES_HOME%\tools\git-*") do if exist "%%g\usr\bin\bash.exe" set "BASH=%%g\usr\bin\bash.exe"
if defined BASH (echo [OK] bash: !BASH!) else (echo [WARN] bash missing - shell tools will not work)
exit /b 0

:PW
echo.
echo --- Playwright ---
if not exist "%VENV_PY%" exit /b 0
if not exist "%UV_EXE%" exit /b 0
"%VENV_PY%" -m playwright --version >nul 2>&1
if errorlevel 1 "%UV_EXE%" pip install --python "%VENV_PY%" --link-mode=copy playwright==1.64.1 >nul 2>&1
set "PWCHR="
for /d %%d in ("%PW_DIR%\chromium*") do set "PWCHR=%%d"
if not defined PWCHR "%VENV_PY%" -m playwright install chromium >nul 2>&1
"%VENV_PY%" -m playwright --version >nul 2>&1
if errorlevel 1 (echo [WARN] Playwright missing) else (echo [OK] Playwright ready)
exit /b 0

:USAGE
echo.
echo   hermes                      Start interactive chat in yolo and resume mode
echo   hermes start                Run messaging gateway in the foreground
echo   hermes update               Install the pinned Hermes Agent release
echo   hermes update --check       Compare installed release, VERSION pin and origin pin
echo   hermes update --force       Rebuild even when the pin and the installed release match
echo   hermes install              Install or repair, then run the setup wizard
echo   hermes launcher             Run launcher (deprecated)
echo   -h, --help                  show this help message and exit
echo.
echo Any other command or flag is passed to the CLI; its full help follows.
echo -- More --
pause >nul
echo.
if exist "%HERMES_EXE%" (
    cd /d "%ROOT%\src\hermes-agent"
    "%HERMES_EXE%" --help 2>nul
)
echo.
echo   App directory: %ROOT%
exit /b 0

:NORUNTIME
echo.
echo [ERROR] No Hermes runtime under "%ROOT%".
echo         Run: hermes install
echo.
exit /b 1

:NOINSTALL
echo.
echo [ERROR] "%ROOT%\scripts\setup-windows.ps1" is missing - not a portable installation.
echo.
exit /b 1

:LOCKFAIL
echo.
echo [ERROR] The runtime is still in use (open hermes session or gateway).
echo         Close it, or run: hermes gateway stop
echo.
exit /b 1
:NOLAUNCHER
echo.
echo [ERROR] launch.bat not found under "%ROOT%".
echo.
exit /b 1
