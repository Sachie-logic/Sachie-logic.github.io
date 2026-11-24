@echo off
rem ---------------------------------------------------------------------------
rem  Double-click this file to publish the blog.
rem  It runs publish.ps1, which commits your changes and pushes to GitHub.
rem  Optional arguments are passed through, e.g.:  publish.cmd -DryRun
rem ---------------------------------------------------------------------------
setlocal
chcp 65001 >nul
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1" %*
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" echo [exit %RC%] publish did not finish successfully.
if not defined PUBLISH_NO_PAUSE (
    echo Press any key to close this window...
    pause >nul
)
exit /b %RC%
