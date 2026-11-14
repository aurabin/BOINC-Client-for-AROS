@echo off
call "%~dp0AROS-starten.cmd" -VirtualDrives %*
exit /b %errorlevel%
