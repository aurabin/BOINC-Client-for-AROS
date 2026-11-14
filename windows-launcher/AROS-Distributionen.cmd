@echo off
call "%~dp0AROS-starten.cmd" -ChooseDistribution %*
exit /b %errorlevel%
