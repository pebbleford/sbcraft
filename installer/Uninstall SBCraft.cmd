@echo off
rem Removes SBCraft from Security Breach.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -Uninstall %*
