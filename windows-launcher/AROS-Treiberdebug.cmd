@echo off
call "%~dp0AROS-starten.cmd" -DriverDebug %*
exit /b %errorlevel%
