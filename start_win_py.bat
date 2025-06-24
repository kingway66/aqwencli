@echo on


SET PATH="%~dp0cygwin64\bin";%PATH%

REM cd /d "%~dp0app"

"C:\Users\pzhz\AppData\Local\Programs\Python\Python313\python.exe" "%~dp0helper_gui\start_gui.py" %*

