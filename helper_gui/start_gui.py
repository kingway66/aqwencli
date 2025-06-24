import os
import sys
import json
import subprocess
import base64
import markdown

from PySide6.QtWidgets import (QApplication, QMainWindow, QVBoxLayout, QHBoxLayout, 
                               QWidget, QTabWidget, QPushButton, QLineEdit, QComboBox,
                               QTextEdit, QLabel, QFrame, QScrollArea, QGridLayout,
                               QDialog, QDialogButtonBox, QMessageBox, QFileDialog,
                               QSplitter)
from PySide6.QtCore import Qt, Signal, QProcess, QThread
from PySide6.QtGui import QFont, QTextCursor
import pathlib

# 默认模型选项
DEFAULT_MODEL_OPTIONS = [
    "qwen-long-2025-01-25",
    "qwen-vl-max", 
    "qwen-long-latest",
    "qwen-turbo-latest",
    "qwen-max-latest"
]

# 每行的默认类型
DEFAULT_ROW_TYPES = ["开关", "开关", "文件", "目录", "文本"]

# 配置文件路径
CONFIG_FILE = "helper_gui.json"


class ParamRow(QWidget):
    row_changed = Signal()

    def __init__(self, app, index):
        super().__init__()
        self.app = app
        self.index = index
        self.setup_ui()
        self.init_default_values()

    def setup_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(5, 3, 5, 3)
        layout.setSpacing(5)

        # 参数类型下拉框
        self.param_type = QComboBox()
        self.param_type.addItems(["开关", "文件", "目录", "文本"])
        self.param_type.setMaximumWidth(80)
        self.param_type.currentTextChanged.connect(self.on_type_change)
        layout.addWidget(self.param_type)

        # Key 输入框
        self.key_entry = QLineEdit()
        self.key_entry.setMaximumWidth(100)
        layout.addWidget(self.key_entry)

        # 值区域容器
        self.value_widget = QWidget()
        self.value_layout = QVBoxLayout(self.value_widget)
        self.value_layout.setContentsMargins(0, 0, 0, 0)
        self.value_layout.setSpacing(2)

        # 单行值输入框（用于开关、文件、目录）
        self.value_combo = QComboBox()
        self.value_combo.setMinimumWidth(300)
        self.value_combo.setEditable(True)  # 允许编辑

        # 多行值输入框（用于文本）
        self.value_text = QTextEdit()
        self.value_text.setMaximumHeight(80)
        self.value_text.setMinimumWidth(300)

        layout.addWidget(self.value_widget, 1)

        # 浏览按钮
        self.browse_btn = QPushButton("...")
        self.browse_btn.setMaximumWidth(30)
        self.browse_btn.clicked.connect(self.browse_file)
        layout.addWidget(self.browse_btn)

        # 加号按钮
        self.plus_btn = QPushButton("+")
        self.plus_btn.setMaximumWidth(25)
        self.plus_btn.clicked.connect(self.add_row)
        layout.addWidget(self.plus_btn)

        # 减号按钮
        self.minus_btn = QPushButton("-")
        self.minus_btn.setMaximumWidth(25)
        self.minus_btn.clicked.connect(self.remove_row)
        layout.addWidget(self.minus_btn)

        # 清除按钮
        self.reset_btn = QPushButton("0")
        self.reset_btn.setMaximumWidth(25)
        self.reset_btn.clicked.connect(self.reset_row)
        layout.addWidget(self.reset_btn)

    def init_default_values(self):
        # 设置默认类型
        row_type = DEFAULT_ROW_TYPES[self.index] if self.index < len(DEFAULT_ROW_TYPES) else "开关"
        self.param_type.setCurrentText(row_type)

        # 设置特殊行的默认值
        if self.index == 0:  # 第一行
            self.key_entry.setText("-m")
            self.value_combo.addItems(DEFAULT_MODEL_OPTIONS)
            self.value_combo.setCurrentText(DEFAULT_MODEL_OPTIONS[0])
        elif row_type == "文本":  # 文本类型的行
            self.key_entry.setText("-dq")
            self.value_text.setPlainText("讲个笑话")

        self.on_type_change()

    def on_type_change(self):
        # 清除现有控件
        for i in reversed(range(self.value_layout.count())):
            child = self.value_layout.itemAt(i).widget()
            if child:
                child.setParent(None)

        # 隐藏浏览按钮
        self.browse_btn.hide()

        ptype = self.param_type.currentText()

        # 根据类型显示对应控件
        if ptype in ["开关", "文件", "目录"]:
            self.value_layout.addWidget(self.value_combo)
            if ptype in ["文件", "目录"]:
                self.browse_btn.show()
        elif ptype == "文本":
            self.value_layout.addWidget(self.value_text)

        self.row_changed.emit()

    def browse_file(self):
        ptype = self.param_type.currentText()
        if ptype == "文件":
            # 构建文件过滤器
            options = [self.value_combo.itemText(i) for i in range(self.value_combo.count())]
            file_filter = ";;".join(options) if options else "所有文件 (*);;文档 (*.pdf *.doc *.docx *.txt);;图片 (*.png *.jpg *.jpeg *.gif)"
            path, _ = QFileDialog.getOpenFileName(self, "选择文件", "", file_filter)
        else:
            path = QFileDialog.getExistingDirectory(self, "选择目录")
        if path:
            self.value_combo.setEditText(path)


    def add_row(self):
        current_type = self.param_type.currentText()
        self.app.add_new_row(self.index + 1, initial_type=current_type)

    def remove_row(self):
        self.app.remove_row(self.index)

    def reset_row(self):
        self.key_entry.clear()
        self.value_combo.clearEditText()
        self.value_text.clear()

    def get_config(self):
        """获取当前行的配置"""
        return {
            'type': self.param_type.currentText(),
            'key': self.key_entry.text(),
            'value': self.value_combo.currentText() if self.param_type.currentText() != "文本" else self.value_text.toPlainText(),
            'options': [self.value_combo.itemText(i) for i in range(self.value_combo.count())]
        }


    def set_config(self, config):
        """设置行的配置"""
        self.param_type.setCurrentText(config.get('type', '开关'))
        self.key_entry.setText(config.get('key', ''))
        if config.get('type') == "文本":
            self.value_text.setPlainText(config.get('value', ''))
        else:
            self.value_combo.clear()
            self.value_combo.addItems(config.get('options', []))
            self.value_combo.setCurrentText(config.get('value', ''))
        self.on_type_change()


class TabPage(QWidget):
    def __init__(self, parent_app, tab_name):
        super().__init__()
        self.parent_app = parent_app
        self.tab_name = tab_name
        self.param_rows = []
        self.setup_ui()
        self.init_default_rows()

    def setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(5)

        # 头部区域（固定高度）
        header_frame = QFrame()
        header_frame.setFixedHeight(120)  # 增加高度以容纳主目录
        header_layout = QVBoxLayout(header_frame)
        header_layout.setContentsMargins(5, 5, 5, 5)

        # 主目录区域
        work_dir_layout = QHBoxLayout()
        work_dir_layout.addWidget(QLabel("主目录:"))
        self.work_dir = QLineEdit()
        default_dir = r"a_qwen_cli"
        self.work_dir.setText(default_dir)
        self.work_dir.setPlaceholderText("如果不为空，将先切换到此目录")
        work_dir_layout.addWidget(self.work_dir)
        
        # 主目录浏览按钮
        self.work_dir_browse = QPushButton("...")
        self.work_dir_browse.setMaximumWidth(30)
        self.work_dir_browse.clicked.connect(self.browse_work_dir)
        work_dir_layout.addWidget(self.work_dir_browse)
        header_layout.addLayout(work_dir_layout)

        # 主命令区域
        cmd_layout = QHBoxLayout()
        cmd_layout.addWidget(QLabel("主命令:"))
        self.main_cmd = QLineEdit()
        #default_cmd = r"c:\cygwin64\bin\bash.exe c:\cygwin64\opt\qwencli\qwencli" if sys.platform == "win32" else r"bash qwen"
        default_cmd = r"bash qwen"
        self.main_cmd.setText(default_cmd)
        cmd_layout.addWidget(self.main_cmd)
        header_layout.addLayout(cmd_layout)

        # 参数列表标签
        header_layout.addWidget(QLabel("参数列表:"))
        layout.addWidget(header_frame)

        # 可滚动的参数区域
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)

        self.param_container = QWidget()
        self.param_layout = QVBoxLayout(self.param_container)
        self.param_layout.setContentsMargins(5, 5, 5, 5)
        self.param_layout.setSpacing(3)
        self.param_layout.addStretch()  # 添加弹性空间

        scroll_area.setWidget(self.param_container)
        layout.addWidget(scroll_area, 1)  # 占用剩余空间

        # 底部按钮区域（固定高度）
        self.create_button_area(layout)

    def browse_work_dir(self):
        """浏览主目录"""
        path = QFileDialog.getExistingDirectory(self, "选择主目录")
        if path:
            self.work_dir.setText(path)

    def create_button_area(self, parent_layout):
        button_frame = QFrame()
        button_frame.setFixedHeight(50)
        button_layout = QHBoxLayout(button_frame)
        button_layout.setContentsMargins(5, 5, 5, 5)

        # 居中容器
        center_widget = QWidget()
        center_layout = QHBoxLayout(center_widget)
        center_layout.setContentsMargins(0, 0, 0, 0)

        buttons = [
            ("帮助文件", self.show_help),
            ("预览命令", self.preview_command),
            ("执行命令", self.execute_command),
            ("重置当前页", self.reset_current_tab)
        ]

        for text, slot in buttons:
            btn = QPushButton(text)
            btn.clicked.connect(slot)
            center_layout.addWidget(btn)

        button_layout.addStretch()
        button_layout.addWidget(center_widget)
        button_layout.addStretch()

        parent_layout.addWidget(button_frame)
    def show_help(self):
        """显示帮助文件"""
        work_dir = self.work_dir.text().strip()
        if not work_dir:
            QMessageBox.warning(self, "警告", "请先设置主目录")
            return
        help_file = pathlib.Path(work_dir) / "help.md"
        try:
            if help_file.exists():
                with open(help_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                # 将 Markdown 转换为 HTML
                html_content = markdown.markdown(content)
            else:
                html_content = f"<p>未找到帮助文件: {help_file}<br>请确认该文件是否存在于主目录下。</p>"
        except Exception as e:
            html_content = f"<p>读取帮助文件时出错：<br>{str(e)}</p>"
        
        # 创建对话框
        dialog = QDialog(self)
        dialog.setWindowTitle(f"帮助文件 - {self.tab_name}")
        dialog.resize(800, 600)
        layout = QVBoxLayout(dialog)
        text_edit = QTextEdit()
        text_edit.setHtml(html_content)  # 设置为 HTML 内容
        text_edit.setReadOnly(True)
        layout.addWidget(text_edit)
        button_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok)
        button_box.accepted.connect(dialog.accept)
        layout.addWidget(button_box)
        dialog.exec()

    def init_default_rows(self):
        """初始化默认行"""
        for i in range(len(DEFAULT_ROW_TYPES)):
            self.add_new_row(i)

    def add_new_row(self, index, initial_type=None):
        new_row = ParamRow(self, index)
        if initial_type:
            new_row.param_type.setCurrentText(initial_type)
            new_row.on_type_change()
        
        new_row.row_changed.connect(self.update_layout)
        self.param_rows.insert(index, new_row)
        self.relayout_rows()
        self.update_layout()

    def remove_row(self, index):
        if len(self.param_rows) > 0:
            row = self.param_rows.pop(index)
            row.setParent(None)
            self.relayout_rows()
            self.update_layout()

    def relayout_rows(self):
        # 清除布局中的所有行
        for i in reversed(range(self.param_layout.count())):
            item = self.param_layout.itemAt(i)
            if item.widget() and isinstance(item.widget(), ParamRow):
                item.widget().setParent(None)

        # 重新添加所有行
        for idx, row in enumerate(self.param_rows):
            row.index = idx
            self.param_layout.insertWidget(idx, row)

    def update_layout(self):
        """更新布局"""
        self.param_container.updateGeometry()

    def build_command(self):
        main_cmd = self.main_cmd.text().strip()
        if not main_cmd:
            raise ValueError("请输入主命令")
        
        params = []

        for row in self.param_rows:
            key = row.key_entry.text().strip()
            if row.param_type.currentText() == "开关":
                value = row.value_combo.currentText().strip()
            elif row.param_type.currentText() == "文本":
                value = row.value_text.toPlainText().strip()
                if value:
                    value = f"'{value}'"
            elif row.param_type.currentText() in ["文件", "目录"]:
                value = row.value_combo.currentText().strip()
                if value:
                    value = f"'{value}'"
            else:
                value = row.value_combo.currentText().strip()

            if key and value:
                params.append(f"{key} {value}")
            elif key:
                params.append(key)
            elif value:
                params.append(value)

        full_command = ' '.join([main_cmd] + params)
        return full_command

    def build_command_to_exec(self):
        main_cmd = self.main_cmd.text().strip()
        if not main_cmd:
            raise ValueError("请输入主命令")
        
        params = []

        for row in self.param_rows:
            key = row.key_entry.text().strip()
            if row.param_type.currentText() == "开关":
                value = row.value_combo.currentText().strip()
            elif row.param_type.currentText() == "文本":
                value = row.value_text.toPlainText().strip()
                if value:
                    #value = f"'{value}'"
                    value = base64.b64encode(value.encode('utf-8')).decode('utf-8')

            elif row.param_type.currentText() in ["文件", "目录"]:
                value = row.value_combo.currentText().strip()
                if value:
                    value = f"'{value}'"
            else:
                value = row.value_combo.currentText().strip()

            if key and value:
                params.append(f"{key} {value}")
            elif key:
                params.append(key)
            elif value:
                params.append(value)

        full_command = ' '.join([main_cmd] + params)
        return full_command

    def preview_command(self):
        try:
            command = self.build_command()
            
            # 如果有主目录，添加切换目录命令
            work_dir = self.work_dir.text().strip()
            full_command_preview = ""
            
            if work_dir:
                if sys.platform == "win32":
                    full_command_preview = f"cd /d \"{work_dir}\"\n"
                else:
                    full_command_preview = f"cd \"{work_dir}\"\n"
            
            full_command_preview += command

            dialog = QDialog(self)
            dialog.setWindowTitle(f"预览命令 - {self.tab_name}")
            dialog.resize(800, 400)

            layout = QVBoxLayout(dialog)
            
            text_edit = QTextEdit()
            text_edit.setFont(QFont("Courier New", 10))
            text_edit.setText(full_command_preview)
            text_edit.setReadOnly(True)
            layout.addWidget(text_edit)

            button_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok)
            button_box.accepted.connect(dialog.accept)
            layout.addWidget(button_box)

            dialog.exec()

        except Exception as e:
            QMessageBox.critical(self, "错误", str(e))



    def execute_command(self):
        """在当前终端中以非阻塞方式执行命令"""
        try:
            # 获取命令和工作目录
            command = self.build_command_to_exec()
            work_dir = self.work_dir.text().strip()

            # 构建完整的命令脚本
            if work_dir:
                if sys.platform == "win32":
                    # Windows 系统
                    script_content = f'cd /d "{work_dir}" && {command}'
                    print(f'> cd /d "{work_dir}"')
                    print(f'> {command}')
                    
                    # 使用 start /B cmd /c 实现非阻塞执行
                    full_command = f'start /B cmd /c "{script_content}"'
                else:
                    # Unix/Linux/macOS 系统
                    script_content = f'cd "{work_dir}" && {command}'
                    print(f'> cd "{work_dir}"')
                    print(f'> {command}')
                    
                    # 直接使用 subprocess.Popen
                    full_command = script_content
            else:
                script_content = command
                print(f'> {command}')
                
                if sys.platform == "win32":
                    # Windows 系统
                    full_command = f'start /B cmd /c "{script_content}"'
                else:
                    # Unix/Linux/macOS 系统
                    full_command = script_content

            # 在后台执行命令（非阻塞）
            process = subprocess.Popen(full_command, shell=True)
            print("命令已启动（后台运行）")
            
        except Exception as e:
            QMessageBox.critical(self, "执行失败", str(e))



    def reset_current_tab(self):
        # 清空现有行
        for row in self.param_rows:
            row.setParent(None)
        self.param_rows.clear()
        
        # 重置主目录和主命令
        #self.work_dir.clear()
        default_dir = r"a_qwen_cli"
        self.work_dir.setText(default_dir)
        #default_cmd = r"c:\cygwin64\bin\bash.exe c:\cygwin64\opt\qwencli\qwencli" if sys.platform == "win32" else r"bash qwen"
        default_cmd = r"bash qwen"
        self.main_cmd.setText(default_cmd)

        # 添加默认行
        self.init_default_rows()
    def get_config(self):
        """获取当前页的配置"""
        return {
            'work_dir': self.work_dir.text(),
            'main_cmd': self.main_cmd.text(),
            'rows': [row.get_config() for row in self.param_rows]
        }

    def set_config(self, config):
        """设置页面配置"""
        # 设置主目录和主命令
        self.work_dir.setText(config.get('work_dir', ''))
        self.main_cmd.setText(config.get('main_cmd', ''))

        # 清空现有行
        for row in self.param_rows:
            row.setParent(None)
        self.param_rows.clear()

        # 根据配置创建行
        rows_config = config.get('rows', [])
        for i, row_config in enumerate(rows_config):
            new_row = ParamRow(self, i)
            new_row.set_config(row_config)
            new_row.row_changed.connect(self.update_layout)
            self.param_rows.append(new_row)
            self.param_layout.insertWidget(i, new_row)



class NameDialog(QDialog):
    def __init__(self, parent, title, label_text, default_text=""):
        super().__init__(parent)
        self.setWindowTitle(title)
        self.setFixedSize(300, 120)

        layout = QVBoxLayout(self)
        layout.addWidget(QLabel(label_text))
        
        self.name_edit = QLineEdit(default_text)
        self.name_edit.selectAll()
        layout.addWidget(self.name_edit)

        button_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        button_box.accepted.connect(self.accept)
        button_box.rejected.connect(self.reject)
        layout.addWidget(button_box)

        self.name_edit.setFocus()

    def get_name(self):
        return self.name_edit.text().strip()


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.tabs = []
        self.setup_ui()
        self.load_config()

    def setup_ui(self):
        self.setWindowTitle("KW CLI Helper")
        
        # 获取屏幕尺寸并设置窗口大小
        screen = QApplication.primaryScreen().geometry()
        window_width = min(700, screen.width() - 100)
        window_height = 600
        
        x = screen.width() - window_width - 50
        y = (screen.height() - window_height) // 2
        
        self.setGeometry(x, y, window_width, window_height)
        self.setMinimumSize(650, 500)

        # 创建中央控件
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        layout = QVBoxLayout(central_widget)
        layout.setContentsMargins(10, 10, 10, 10)
        layout.setSpacing(5)

        # 创建Tab控件
        self.tab_widget = QTabWidget()
        self.tab_widget.setMovable(True)  # 启用Tab拖动排序
        layout.addWidget(self.tab_widget, 1)  # 占用大部分空间

        # 创建全局按钮区域
        self.create_global_buttons(layout)

        # 创建初始Tab
        self.add_tab("Tab 1")

    def create_global_buttons(self, parent_layout):
        # 创建固定高度的按钮框架
        button_frame = QFrame()
        button_frame.setFixedHeight(50)
        button_layout = QHBoxLayout(button_frame)
        button_layout.setContentsMargins(5, 5, 5, 5)

        # 创建居中容器
        center_widget = QWidget()
        center_layout = QHBoxLayout(center_widget)
        center_layout.setContentsMargins(0, 0, 0, 0)

        buttons = [
            ("添加Tab", self.add_tab_dialog),
            ("删除Tab", self.remove_current_tab),
            ("改名Tab", self.rename_tab_dialog),
            ("复制Tab", self.copy_current_tab),  # 新增复制Tab按钮
            ("保存", self.save_config),
            ("重置", self.reset_all),
            ("README", self.show_readme),
            ("退出", self.close)
        ]

        for text, slot in buttons:
            btn = QPushButton(text)
            btn.clicked.connect(slot)
            center_layout.addWidget(btn)

        button_layout.addStretch()
        button_layout.addWidget(center_widget)
        button_layout.addStretch()

        parent_layout.addWidget(button_frame)

    def add_tab(self, tab_name=None):
        if tab_name is None:
            tab_name = f"Tab {len(self.tabs) + 1}"
        
        tab_page = TabPage(self, tab_name)
        self.tabs.append(tab_page)
        self.tab_widget.addTab(tab_page, tab_name)
        
        # 选择新创建的tab
        self.tab_widget.setCurrentIndex(len(self.tabs) - 1)

    def add_tab_dialog(self):
        dialog = NameDialog(self, "添加新Tab", "Tab名称:", f"Tab {len(self.tabs) + 1}")
        if dialog.exec() == QDialog.DialogCode.Accepted:
            name = dialog.get_name()
            if name:
                self.add_tab(name)

    def copy_current_tab(self):
        """复制当前Tab"""
        current_index = self.tab_widget.currentIndex()
        if current_index < 0:
            QMessageBox.warning(self, "警告", "没有可复制的Tab")
            return
        # 获取当前Tab的配置
        current_tab = self.tabs[current_index]
        base_name = f"{current_tab.tab_name} (副本)"
        new_name = base_name
        suffix = 1
        while any(tab.tab_name == new_name for tab in self.tabs):
            new_name = f"{base_name} ({suffix})"
            suffix += 1
        # 创建新的Tab
        tab_config = {
            'name': new_name,
            'config': current_tab.get_config()
        }
        new_tab_page = TabPage(self, tab_config['name'])
        new_tab_page.set_config(tab_config['config'])
        self.tabs.append(new_tab_page)
        self.tab_widget.addTab(new_tab_page, tab_config['name'])
        # 选择新创建的Tab
        self.tab_widget.setCurrentIndex(len(self.tabs) - 1)

    def remove_current_tab(self):
        if len(self.tabs) <= 1:
            QMessageBox.warning(self, "警告", "至少需要保留一个Tab页")
            return

        current_index = self.tab_widget.currentIndex()
        current_tab = self.tabs[current_index]
        
        reply = QMessageBox.question(self, "确认", 
                                   f"确定要删除 '{current_tab.tab_name}' 吗？",
                                   QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        
        if reply == QMessageBox.StandardButton.Yes:
            self.tabs.pop(current_index)
            self.tab_widget.removeTab(current_index)

    def rename_tab_dialog(self):
        current_index = self.tab_widget.currentIndex()
        current_tab = self.tabs[current_index]

        dialog = NameDialog(self, "重命名Tab", "新名称:", current_tab.tab_name)
        if dialog.exec() == QDialog.DialogCode.Accepted:
            new_name = dialog.get_name()
            if new_name:
                current_tab.tab_name = new_name
                self.tab_widget.setTabText(current_index, new_name)

    def reset_all(self):
        """全部重置功能"""
        reply = QMessageBox.question(self, "确认", "确定要重置所有Tab页的配置吗？\n将从 helper_gui.json.example 加载默认配置。",
                                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        
        if reply == QMessageBox.StandardButton.Yes:
            if os.path.exists("helper_gui.json.example"):
                self.load_config("helper_gui.json.example")
                QMessageBox.information(self, "成功", "已从 helper_gui.json.example 重置配置")
            else:
                # 如果示例文件不存在，创建默认tab
                self.tabs.clear()
                self.tab_widget.clear()
                self.add_tab("Tab 1")
                QMessageBox.warning(self, "警告", "未找到 helper_gui.json.example，已创建默认Tab")


    def save_config(self):
        try:
            #config = {'tabs': []}
            config = {
                'tabs': [],
                'last_selected_tab': self.tab_widget.currentIndex()
            }            
            # 按照 QTabWidget 的当前顺序保存
            for i in range(self.tab_widget.count()):
                tab_page = self.tab_widget.widget(i)  # 获取当前索引的 TabPage 对象
                tab_config = {
                    'name': tab_page.tab_name,
                    'config': tab_page.get_config()
                }
                config['tabs'].append(tab_config)
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(config, f, ensure_ascii=False, indent=2)
            QMessageBox.information(self, "成功", f"配置已保存到 {CONFIG_FILE}")
        except Exception as e:
            QMessageBox.critical(self, "保存失败", f"无法保存配置文件：{str(e)}")


    def load_config(self, config_file=None):
        """加载配置文件"""
        try:
            if config_file is None:
                # 默认优先级：主配置文件 -> 示例配置文件 -> 创建默认tab
                if os.path.exists(CONFIG_FILE):
                    config_file = CONFIG_FILE
                elif os.path.exists("helper_gui.json.example"):
                    config_file = "helper_gui.json.example"
                else:
                    self.add_tab("Tab 1")
                    return
            if not os.path.exists(config_file):
                QMessageBox.warning(self, "警告", f"配置文件 {config_file} 不存在")
                return
            with open(config_file, 'r', encoding='utf-8') as f:
                config = json.load(f)
            # 清空现有tabs
            self.tabs.clear()
            self.tab_widget.clear()
            # 根据配置重建tabs
            tabs_config = config.get('tabs', [])
            if not tabs_config:
                self.add_tab("Tab 1")
                return
            for tab_config in tabs_config:
                tab_name = tab_config.get('name', 'Tab')
                tab_page = TabPage(self, tab_name)
                tab_page.set_config(tab_config.get('config', {}))
                self.tabs.append(tab_page)
                self.tab_widget.addTab(tab_page, tab_name)
            # 恢复最后选中的Tab
            last_selected_tab = config.get('last_selected_tab', 0)
            if 0 <= last_selected_tab < len(self.tabs):
                self.tab_widget.setCurrentIndex(last_selected_tab)
        except Exception as e:
            QMessageBox.critical(self, "加载失败", f"无法加载配置文件：{str(e)}")
            if not self.tabs:
                self.add_tab("Tab 1")
                        

    def show_readme(self):
        import markdown
        readme_path = pathlib.Path(__file__).parent / "README.md"
        try:
            with open(readme_path, 'r', encoding='utf-8') as f:
                content = f.read()
            # 将 Markdown 转换为 HTML
            html_content = markdown.markdown(content)
        except FileNotFoundError:
            html_content = "<p>未找到 README.md 文件。<br>请确认该文件是否存在于当前目录下。</p>"
        except Exception as e:
            html_content = f"<p>读取 README.md 文件时出错：<br>{str(e)}</p>"
        
        # 创建对话框
        dialog = QDialog(self)
        dialog.setWindowTitle("帮助 - README")
        dialog.resize(800, 600)
        layout = QVBoxLayout(dialog)
        text_edit = QTextEdit()
        text_edit.setHtml(html_content)  # 设置为 HTML 内容
        text_edit.setReadOnly(True)
        layout.addWidget(text_edit)
        button_box = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok)
        button_box.accepted.connect(dialog.accept)
        layout.addWidget(button_box)
        dialog.exec()



    def closeEvent(self, event):
        """窗口关闭时自动保存配置"""
        #self.save_config()
        event.accept()


if __name__ == "__main__":
    app = QApplication(sys.argv)
    
    # 设置应用程序样式
    app.setStyle('Fusion')
    
    window = MainWindow()
    window.show()
    
    sys.exit(app.exec())
