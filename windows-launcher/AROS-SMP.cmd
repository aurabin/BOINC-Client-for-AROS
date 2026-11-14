@echo off
call "%~dp0AROS-starten.cmd" -SmpCpus 4 %*
exit /b %errorlevel%
