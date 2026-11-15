@echo off
call "%~dp0AROS-starten.cmd" -OfflineIso %*
exit /b %errorlevel%
