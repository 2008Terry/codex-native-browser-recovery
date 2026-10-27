@echo off
echo COMMUNITY WORKAROUND - NOT AN OFFICIAL OPENAI FIX
echo Only one exact known helper image is supported.
echo Repair invalidates the helper's OpenAI signature. Read README.md first.
echo Save your work and fully quit Codex before applying.
choice /C YN /N /M "Accept this signature change and apply? [Y/N] "
if errorlevel 2 exit /b 1
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0ComputerUse.ps1" -Action Repair -AcceptSignatureChange
set "cu_exit=%errorlevel%"
echo.
echo Exit code: %cu_exit%
pause
exit /b %cu_exit%
