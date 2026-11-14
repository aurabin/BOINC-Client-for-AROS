@echo off
call "%~dp0AROS-starten.cmd" -AutoUpdate %*
exit /b %errorlevel%
