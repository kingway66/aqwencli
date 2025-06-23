#!/bin/bash

# 检查参数数量
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "用法: $0 [-f|--force] <apikey> <output_path>"
    exit 1
fi

# 解析参数
FORCE=false
if [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
    FORCE=true
    API_KEY="$2"
    OUTPUT_FILE="$3/apikey.json"
else
    API_KEY="$1"
    OUTPUT_FILE="$2/apikey.json"
fi

# 检查目标文件是否已存在
if [ -f "$OUTPUT_FILE" ] && ! $FORCE; then
    echo "❌ 错误: 文件已存在: $OUTPUT_FILE"
    echo "如需覆盖，请使用 -f 或 --force 参数。"
    exit 1
fi

# 对 API KEY 进行 base64 编码
ENCODED_KEY=$(echo -n "$API_KEY" | base64)

# 创建目标目录（如果不存在）
mkdir -p "$(dirname "$OUTPUT_FILE")"

# 写入 JSON 文件
cat << EOF > "$OUTPUT_FILE"
{
  "api_key": "$ENCODED_KEY"
}
EOF

echo "✅ API Key 已写入: $OUTPUT_FILE"
