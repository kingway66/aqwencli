@echo off


SET PATH="%~dp0cygwin64\bin";%PATH%

REM cd /d "%~dp0app"

"%~dp0helper_gui_win.dist\start_gui.exe" %*

