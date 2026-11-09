@echo off
rem Terminal Jarvis: sends "codex" through Jarvis (see route.ps1). Remove with uninstall.ps1.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\TerminalJarvis\voice\route.ps1" %*
exit /b %ERRORLEVEL%
