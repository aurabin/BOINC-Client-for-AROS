@echo off
call "%~dp0AROS-starten.cmd" -Smp %*
exit /b %errorlevel%
