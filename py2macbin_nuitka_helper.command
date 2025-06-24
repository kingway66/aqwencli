#!/bin/bash

nuitka --standalone --enable-plugin=pyside6 --output-dir=out helper_gui/start_gui.py
