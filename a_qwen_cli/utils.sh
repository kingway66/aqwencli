#!/bin/bash

validate_json() {
    local json="$1"
    if [ -z "$json" ]; then
        return 1
    fi
    echo "$json" | jq empty 2>/dev/null
    return $?
}

# 依赖检查
check_dependencies() {
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            error "错误: 需要安装 $cmd"
            exit 1
        fi
    done
}

# 安装xxhash工具检查（如果没有则自动安装）
check_xxhash() {
    if ! command -v xxhsum &> /dev/null; then
        warn "检测到未安装xxHash，正在尝试安装..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get install -y xxhash || sudo yum install -y xxhash
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install xxhash
        else
            error "错误: 无法自动安装xxHash，请手动安装"
            exit 1
        fi
    fi
}

# 计算文件xxHash (64位) - 修复空值问题
calculate_xxhash() {
    local file="$1"
    if [ ! -f "$file" ]; then
        warn "null"
        return
    fi
    xxhsum "$file" 2>/dev/null | awk '{print $1}' || echo "null"
}




# ====================
# = 工具函数：获取调用上下文信息 =
# ====================
get_log_prefix() {
    local level="$1"

    # 获取调用栈信息
    local filename=$(basename "${BASH_SOURCE[1]}")
    local lineno="${BASH_LINENO[0]}"
    local funcname="${FUNCNAME[1]}"

    # 构造前缀
    local prefix="[$level] [$filename:$lineno]"
    if [[ -n "$funcname" ]]; then
        prefix+="[$funcname]"
    fi

    echo -n "$prefix"
}

# ==================
# = 日志输出函数 =
# ==================

log_output() {
    local level="$1"
    local message="$2"

    # 构造带颜色的终端输出
    local color=""
    case "$level" in
        DEBUG) color="\033[36m";;  # debug 蓝绿色
        INFO) color="\033[32m";;  # info 绿色
        WARN) color="\033[33m";;  # warn 黄色
        ERROR) color="\033[31m";;  # error 红色
    esac

    if [[ $level == "DEBUG" ]]; then
        local colored_line="$color$(get_log_prefix "$level") $message\033[0m"
    else
        local colored_line="$color$message\033[0m"
    fi

    # 构造无颜色的日志行用于写入文件
    local plain_line="$(get_log_prefix "$level") $message"

    # 写入文件（无颜色）
    if [ -n "$LOG_FILE" ]; then
        echo "$plain_line" >> "$LOG_FILE"
    fi

    # 输出到终端（带颜色）
    echo -e "$colored_line" >&2
}

debug() { [ "$LOG_ENABLE" != true ] && return; [ "$LOG_DEBUG" != true ] && return; log_output "DEBUG" "$*"; }
info()  { [ "$LOG_ENABLE" != true ] && return; [ "$LOG_INFO"  != true ] && return; log_output "INFO" "$*"; }
warn()  { [ "$LOG_ENABLE" != true ] && return; [ "$LOG_WARN"  != true ] && return; log_output "WARN" "$*"; }
error() { [ "$LOG_ENABLE" != true ] && return; [ "$LOG_ERROR" != true ] && return; log_output "ERROR" "$*"; }

# ==================
# = 示例使用 =
# ==================
function connect_db() {
    debug "正在连接数据库..."
    info "连接成功"
    warn "这是一个警告"
    error "这是一个错误"

    a=$(jq -n {"abc":300})
    error $a
}

#connect_db
#debug "这是主流程的调试信息"



add_array_to_array() {
    local json1="$1"
    local json2="$2"

    jq -c --argjson a "$json1" --argjson b "$json2" '$a + $b' <<< '{}'
}


add_file_to_array() {
    local json="$1"
    local value="$2"

    # 如果 $json 为空或不是合法 JSON 数组，初始化为 []
    if [ -z "${json:-}" ] || ! jq -e . <<< "$json" &>/dev/null; then
        json="[]"
    fi

    # 使用 --argjson 添加新项到数组
    jq -c --arg v "$value" '. += [$v]' <<< "$json"
}


add_file_to_json() {
    local json="$1"
    local fileid="$2"
    local filepath="$3"
    local filename=$(basename "$filepath")
    local size=$(wc -c < "$filepath")

    jq --arg id "$fileid" \
       --arg path "$filepath" \
       --arg name "$filename" \
       --arg sz "$size" \
       '.files += [{id: $id, filepath: $path, filename: $name, size: ($sz | tonumber)}]' <<< "$json"
}


find_with_exts() {
  local path="$1"
  shift
  local ext 
  local conditions=()

  # 构建 find 的条件数组
  for ext; do
    if [ ${#conditions[@]} -eq 0 ]; then
      conditions=(-iname "*.$ext")
    else
      conditions+=( -o -iname "*.$ext" )
    fi  
  done

  if [ ${#conditions[@]} -gt 0 ]; then
    # 使用数组拼接完整 find 命令参数
    find_args=( "$path" -type f '(' "${conditions[@]}" ')' -and ! -name ".*" -print0 )

    # 打印调试信息（注意要展开数组）
    #echo "Running: find ${find_args[*]}"
    #FIND="/usr/bin/find"
    # 安全执行 find
    find "${find_args[@]}" | jq -Rs 'split("\u0000")[:-1]'
  else
    error "❌ 未提供有效的扩展名"
  fi  
}

# 测试调用
#find_with_exts . sh

b(){
local path="$1"

while read line;do
 debug "ssss $line eeee"
done < <(find_with_exts $path sh|jq -r '.[]')

}



# 函数：查找指定目录中具有指定扩展名的文件
find_with_exts_with_hidden() {
  local path="$1"     # 第一个参数是路径
  shift               # 剩下的参数是扩展名列表

  local conditions="" # 构建 find 的条件表达式
  local first=1       # 控制是否添加 "-o"

  for ext; do
    if [ $first -eq 1 ]; then
      conditions=" -iname \"*.$ext\""
      first=0
    else
      conditions="$conditions -o -iname \"*.$ext\""
    fi
  done

  if [ -n "$conditions" ]; then
    find "$path" -type f $conditions
  else
    error "❌ 未提供有效的扩展名"
  fi
}

contains_element() {
    local element=$1
    shift
    local array=("$@")
    debug "Searching for element '$element' in array: ${array[@]}"  # 输出数组内容
    for item in "${array[@]}"; do
        debug "Checking item: $item"  # 输出正在检查的元素
        if [[ "$item" == "$element" ]]; then
            return 0  # 找到，返回成功
        fi
    done
    return 1  # 没找到，返回失败
}


returnd() {
    # func: pass a json like return,add a status key
    # useage: returnd return_msg return_status
    # output: {"return":return_msg,"status":"outputid"}
    # 注意：使用时returnd 下面可以跟一行return 0或return 1，实现直接退出
    # 检查第一个参数是否为数字
    : '
    the_msg=
    {
      files:{
        [
          {"filename":"1.txt","fileid":"abcxxx","filepath":"xxxx"},
          {"filename":"2.txt","fileid":"defxxx","filepath":"xxxx"},
          ]},
      status: "ok",
      return: {} 
      return: {
        "filename":"1.txt",
        "fileid":"abcxxx"
      }
    }
    
    the_msg=
    {
     send:{},
     status: "ok"
     }


    '
    if [[ $1 =~ ^[+-]?[0-9]*\.?[0-9]+$ ]]; then
        # 数字类型，不加双引号
        msg=\{\"return\":$1,\"status\":\"$2\"}
    #elif [[ $1 == \[* ]] || [[ $1 == \{* ]]; then
        # 如果是数组或字典（以 [ 或 { 开头），直接使用不加额外双引号
    #    msg=\{\"return\":$1,\"status\":\"$2\"}
    else
        # 字符串类型，加双引号
        msg=\{\"return\":\"$1\",\"status\":\"$2\"}
    fi
    echo "$msg"
}

# 新版 jqd：支持提取 .return 或 .status 等字段
jqd() {
    local json="$1"
    local field="${2:-return}"  # 默认是 return，否则使用传入参数

    # 使用 jq 提取字段值，-r 表示原始字符串输出
    local value=$(echo "$json" | jq -r ".$field")

    echo "$value"
}


