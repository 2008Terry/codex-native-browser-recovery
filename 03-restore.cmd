@echo off
echo Restore returns the exact old official helper from your verified local backup.
echo The original browser failure may return.
echo Save your work and fully quit Codex first.
choice /C YN /N /M "Restore the original component? [Y/N] "
if errorlevel 2 exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0ComputerUse.ps1" -Action Restore -ConfirmRestore
set "cu_exit=%errorlevel%"
echo.
echo Exit code: %cu_exit%
pause
exit /b %cu_exit%
