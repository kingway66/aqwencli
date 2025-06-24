#!/bin/bash

set -euo pipefail

# 检查是否传入了参数
if [ -z "$1" ]; then
  echo "请提供JSON文件路径作为参数。例如：$0 filename.json"
  exit 1
fi

if [ -z "$2" ]; then
  echo "$1 未提供保存路径，无需创建md文件。"
  exit 1
fi

json_file="$1"
md_path="$2"

# 检查文件是否存在
if [ ! -f "$json_file" ]; then
  echo "错误：文件 '$json_file' 不存在。"
  exit 1
fi


# 提取用户提示词的第一行
user_prompt=$(jq -r '.request.messages[] | select(.role == "user") | .content' "$json_file" | head -n 1)

# 替换掉可能引起文件名错误的字符（如斜杠、空格等）
safe_user_prompt=$(echo "$user_prompt" | sed 's/[\\/\:*?"<>|]/_/g' | sed 's/ /_/g')

# 提取时间戳（假设文件名格式是类似 api_response_1749287843.json）
filename_base=$(basename "$json_file" .json)
timestamp=$(echo "$filename_base" | grep -oE '[0-9]+$')

# 判断是否有合法时间戳
if [[ -z "$timestamp" || ${#timestamp} -lt 10 ]]; then
  echo "错误：无法从文件名 '$json_file' 中提取有效的时间戳。"
  exit 1
fi

#!/bin/bash

# 获取系统信息
os_name=$(uname -s)

# 判断平台
if [[ "$os_name" == "Darwin" ]]; then
    echo "Platform: macOS"
    formatted_time=$(date -jf "%s" "$timestamp" +"%Y-%m-%d_%H-%M-%S" 2>/dev/null)

elif [[ "$os_name" == "Linux" ]]; then
    # 检查是否是 Windows Subsystem for Linux (WSL)
    if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
        echo "Platform: Windows (WSL)"
    else
        echo "Platform: Linux"
    fi
    formatted_time=$(date -jf "%s" "$timestamp" +"%Y-%m-%d_%H-%M-%S" 2>/dev/null)

elif [[ "$os_name" == "CYGWIN"* || "$os_name" == "MINGW"* || "$os_name" == "MSYS"* ]]; then
    echo "Platform: Windows ($os_name)"
    formatted_time=$(date --date="@$timestamp" +"%Y-%m-%d_%H-%M-%S" 2>/dev/null)
else
    echo "Unknown platform"
    formatted_time=$(date -jf "%s" "$timestamp" +"%Y-%m-%d_%H-%M-%S" 2>/dev/null)
fi


# 将时间戳转换为标准格式 YYYY-MM-DD_HH-mm-SS
#formatted_time=$(date -jf "%s" "$timestamp" +"%Y-%m-%d_%H-%M-%S" 2>/dev/null)
#formatted_time=$(date --date="@$timestamp" +"%Y-%m-%d_%H-%M-%S" 2>/dev/null)

if [ $? -ne 0 ]; then
  echo "错误：时间戳 '$timestamp' 转换失败，请确认是合法的 Unix 时间戳。"
  exit 1
fi

# 构造新的Markdown文件名
new_md_file="${formatted_time}_${safe_user_prompt}.md"

# 写入目录为当前目录或指定日志目录
output_file="$md_path/$new_md_file"

# 提取其他字段
model_name=$(jq -r '.request.model' "$json_file")

# 只提取 files[0] 的信息，若无文件则设为“无”
file_id=$(jq -r 'if .request.files and (.request.files | length > 0) then .request.files[0].id else "无" end' "$json_file")
filename=$(jq -r 'if .request.files and (.request.files | length > 0) then .request.files[0].filename else "无" end' "$json_file")
filepath=$(jq -r 'if .request.files and (.request.files | length > 0) then .request.files[0].filepath else "无" end' "$json_file")

response_content=$(jq -r '.response.choices[0].message.content' "$json_file")

# 写入Markdown文件
mkdir -p "$(dirname "$output_file")"
cat << EOF > "$output_file"
# $user_prompt

$response_content

*模型名称：$model_name  
文件ID：$file_id  
文件名：$filename  
文件路径：$filepath*

EOF

echo "✅ Markdown 文件已生成：$output_file"
