@echo off
setlocal
set SCRIPT_DIR=%~dp0
REM Optional: append -InstallDeps to run ohpm install when node_modules is missing
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build.ps1" %*
exit /b %ERRORLEVEL%
