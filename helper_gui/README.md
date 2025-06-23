# 本项目是一个cli执行器，和一个qwenlong脚本。

## 代码由AI写成，我做了少量修改调试。
## USE AT YOUR OWN RISK

## 一、cli helper也可以执行其他的命令，是个通用工具，可以自由增减开关和参数，保存和加载配置。

### 多行文本会被转换为base64，为避免特殊字符断行，需在脚本中转换回来。
### 单行文本会保留原样，用单引号包裹
### cli helper的依赖：pyside6 markdown

## 二、aqwencli主要是用于qwenlong，其说明见tab页的帮助文件。

### aqwencli的依赖：curl jq bash(coreutils)
### 如果不想安装上面这些依赖，可以使用打包好的执行文件，windows版自带精简cygwin。
### windows下的微软电脑管家，会导致脚本运行特别慢，务必关闭。

## 三、cli helper的配置说明。

### 每一行有三个组件，type/key/value，类型type有开关、文件、目录、文本四种。
### key即选项(option)或标志(flag),比如-c,-m,--output
### value即选项的值或者直接参数，当本行类型为开关、文件、目录时，为带下拉框的单行文本
### 当本行类型为文本时，为多行文本，会启用base64编码后发送，主命令需对应解码
### 配置文件中的options:[]
    当本行类型为开关时，为下拉框的选择值，如options:["qwen-long","qwen-turbo"]
    当本行类型为文件时，为qt文件筛选器，格式为optsions:["文本文件 (*.txt)", "文档 (*.pdf *.docx)"]
    如果没有文件筛选器，则为"所有文件 (*);;文档 (*.pdf *.doc *.docx *.txt);;图片 (*.png *.jpg *.jpeg *.gif)"
### 命令组合的原则
    1. 如果有主目录，先cd(win下为cd /d)到主目录；
    2. 然后执行命令：主命令 加上所有非空的option 和所有非空的 value
### 目录和文件
    1. helper即为本gui，用pyside6写成；
    2. 对应的脚本最好单独写一个目录，比如a_qwen_cli
    3. tab的帮助文件即读取脚本目录下的help.md
    4. 系统命令可以不需要主目录
    5. win下会将cygwin64/bin设置为path，可直接执行bash等命令

    
