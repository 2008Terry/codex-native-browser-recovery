@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0ComputerUse.ps1" -Action Check
set "cu_exit=%errorlevel%"
echo.
echo Read README.md for status meanings. File checks are not native browser acceptance.
echo Exit code: %cu_exit%
pause
exit /b %cu_exit%
