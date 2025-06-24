@echo on


"C:\Users\pzhz\AppData\Local\Programs\Python\Python313\python.exe" -m nuitka --standalone --enable-plugin=pyside6 --output-dir=out "%~dp0helper_gui\start_gui.py" %*

