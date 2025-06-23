#!/bin/bash


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载同目录下的 utils.sh
LOG_DIR="$SCRIPT_DIR/log_dir"
CONFIG_JSON="$SCRIPT_DIR/config.json"
APIKEY_JSON="$SCRIPT_DIR/apikey.json"

# 添加缓存相关的全局变量
CACHE_FILE="$SCRIPT_DIR/qwenlong_cache.json"


# 全局变量
upload_host=""
upload_dir=""
policy=""
signature=""
oss_access_key_id=""
x_oss_object_acl=""
x_oss_forbid_overwrite=""
key=""
user_question=""
model_name="qwen-vl-max-latest"  # 默认模型

# 使用普通数组替代关联数组
file_urls_keys=()
file_urls_values=()



# 创建日志目录
log_dir="$SCRIPT_DIR/qwenvl_log_dir"
mkdir -p "$log_dir"



# 添加缓存相关的全局变量
# cache_dir="${HOME}/.cache/image_chat"
cache_file="$SCRIPT_DIR/qwenvl_cache.json"
# mkdir -p "$cache_dir"

# 计算文件的MD5哈希值
get_file_hash() {
    local file_path="$1"
    md5sum "$file_path" | awk '{print $1}'
}

# 获取文件大小（用于额外验证）
get_file_size() {
    local file_path="$1"
    stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path"
}

# 从缓存中获取OSS URL
get_cached_url() {
    local file_hash="$1"
    local file_size="$2"
    local current_time=$(date +%s)

    if [ ! -f "$cache_file" ]; then
        echo "{}" > "$cache_file"
        return 1
    fi

    # 读取缓存并检查是否存在且未过期
    local cached_data=$(jq -r --arg hash "$file_hash" --arg size "$file_size" \
        '.[$hash] | select(.size == $size and (.timestamp + 172800) > now)' \
        --argjson now "$current_time" "$cache_file")

    if [ -n "$cached_data" ]; then
        echo "$cached_data" | jq -r '.url'
        return 0
    fi
    return 1
}

# 更新缓存
update_cache() {
    local file_hash="$1"
    local file_size="$2"
    local oss_url="$3"
    local current_time=$(date +%s)

    # 创建新的缓存条目
    local new_entry="{\"url\": \"$oss_url\", \"size\": \"$file_size\", \"timestamp\": $current_time}"

    # 更新缓存文件
    if [ -f "$cache_file" ]; then
        # 删除过期条目并添加新条目
        jq --arg hash "$file_hash" --arg entry "$new_entry" \
            'del(.[] | select(.timestamp + 172800 < now)) * . + {($hash): ($entry|fromjson)}' \
            --argjson now "$current_time" "$cache_file" > "${cache_file}.tmp" && \
        mv "${cache_file}.tmp" "$cache_file"
    else
        # 创建新的缓存文件
        echo "{\"$file_hash\": $new_entry}" > "$cache_file"
    fi
}

# 修改上传单个文件的函数
upload_single_file() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        echo "❌ 错误: 文件不存在: $file_path"
        return 1
    fi

    local file_hash=$(get_file_hash "$file_path")
    local file_size=$(get_file_size "$file_path")
    local cached_url=$(get_cached_url "$file_hash" "$file_size")

    if [ -n "$cached_url" ]; then
        echo "🔄 使用缓存的文件: $file_path"
        file_urls_keys[${#file_urls_keys[@]}]="$(basename "$file_path")"
        file_urls_values[${#file_urls_values[@]}]="$cached_url"
        return 0
    fi

    echo "🔄 正在上传新文件: $file_path..."
    local file_key="${upload_dir}/$(basename "$file_path")"

    local response=$(curl -s -X POST "$upload_host" \
        -F "OSSAccessKeyId=$oss_access_key_id" \
        -F "Signature=$signature" \
        -F "policy=$policy" \
        -F "key=$file_key" \
        -F "x-oss-object-acl=$x_oss_object_acl" \
        -F "x-oss-forbid-overwrite=$x_oss_forbid_overwrite" \
        -F "success_action_status=200" \
        -F "file=@$file_path")

    if [ $? -eq 0 ]; then
        echo "✅ 文件上传成功: $file_path"
        local oss_url="oss://$file_key"
        file_urls_keys[${#file_urls_keys[@]}]="$(basename "$file_path")"
        file_urls_values[${#file_urls_values[@]}]="$oss_url"
        
        # 更新缓存
        update_cache "$file_hash" "$file_size" "$oss_url"
        return 0
    else
        echo "❌ 错误: 文件上传失败: $file_path"
        return 1
    fi
}

# 添加缓存清理函数（可选择性地在脚本启动时调用）
cleanup_cache() {
    if [ -f "$cache_file" ]; then
        local current_time=$(date +%s)
        jq 'del(.[] | select(.timestamp + 172800 < now))' \
            --argjson now "$current_time" "$cache_file" > "${cache_file}.tmp" && \
        mv "${cache_file}.tmp" "$cache_file"
    fi
}




# 显示使用帮助
show_help() {
    echo "使用方法: $0 [选项] <图片1> [图片2] ... [问题]"
    echo "选项:"
    echo "  -m, --model   指定模型名称 (默认: qwen-vl-max-latest)"
    echo "  -h, --help    显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 image1.png image2.png \"描述这些图片\""
    echo "  $0 -m qwen-vl-plus image1.png \"这是什么图片？\""
    exit 1
}

# 1. 获取上传凭证
get_upload_policy() {
    echo "🔄 步骤1: 获取上传凭证..."
    local response=$(curl -s -X GET "https://dashscope.aliyuncs.com/api/v1/uploads?action=getPolicy&model=$model_name" \
        -H "Authorization: $DASHSCOPE_API_KEY" \
        -H "Content-Type: application/json")

    # 解析JSON并设置变量
    upload_host=$(echo "$response" | jq -r '.data.upload_host')
    upload_dir=$(echo "$response" | jq -r '.data.upload_dir')
    policy=$(echo "$response" | jq -r '.data.policy')
    signature=$(echo "$response" | jq -r '.data.signature')
    oss_access_key_id=$(echo "$response" | jq -r '.data.oss_access_key_id')
    x_oss_object_acl=$(echo "$response" | jq -r '.data.x_oss_object_acl')
    x_oss_forbid_overwrite=$(echo "$response" | jq -r '.data.x_oss_forbid_overwrite')

    if [ -z "$policy" ] || [ -z "$upload_host" ]; then
        echo "❌ 错误: 获取上传凭证失败"
        exit 1
    fi

    echo "✅ 成功获取上传凭证"
}

# 2. 上传单个文件


# 3. 上传多个文件
upload_files() {
    local success=true
    local files=("$@")
    for file in "${files[@]}"; do
        upload_single_file "$file" || success=false
    done
    
    if [ "$success" = false ]; then
        echo "❌ 部分文件上传失败"
        exit 1
    fi
}

# 4. 生成多图片对话JSON
generate_image_json() {
    local json_content='{"model": "'"$model_name"'", "messages": [{"role": "user", "content": ['
    json_content+='{"type": "text", "text": "'"$user_question"'"},'
    
    local first=true
    local i
    for i in "${!file_urls_values[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json_content+=","
        fi
        json_content+='{"type": "image_url", "image_url": {"url": "'"${file_urls_values[$i]}"'"}}'
    done
    
    json_content+=']}]}'
    echo "$json_content"
}

# 5. 调用模型API并处理响应
call_model_api() {
    echo "🔄 步骤3: 调用模型($model_name)API进行多图对话（非流式输出，请耐心等待几秒）..."
    local json_data=$(generate_image_json)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="$log_dir/chat_${timestamp}.json"
    
    # 保存用户输入
    echo "{\"user_input\": {\"model\": \"$model_name\", \"question\": \"$user_question\", \"images\": [" > "$log_file"
    local first=true
    for img in "${file_urls_values[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$log_file"
        fi
        echo "\"$img\"" >> "$log_file"
    done
    echo "]}, " >> "$log_file"
    
    # 调用API并获取响应
    local response=$(curl -s -X POST "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions" \
        -H "Authorization: $DASHSCOPE_API_KEY" \
        -H "Content-Type: application/json" \
        -H "X-DashScope-OssResourceResolve: enable" \
        -d "$json_data")
    
    # 提取并显示content内容
    local content=$(echo "$response" | jq -r '.choices[0].message.content')
    echo -e "\n🤖 模型回答："
    echo "$content"
    
    # 保存完整对话记录
    echo "\"response\": $response}" >> "$log_file"
    echo "💾 对话记录已保存到: $log_file"
}

# 解析命令行参数
parse_args() {
    local files=()
    local parsing_files=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -m|--model)
                if [ -n "$2" ]; then
                    model_name="$2"
                    shift 2
                else
                    echo "错误: -m|--model 选项需要一个参数"
                    exit 1
                fi
                ;;
	       -dq)
                user_question=$(echo "$2" | base64 --decode)
                shift 2
                ;;

            *)
                if [ -f "$1" ]; then
                    files+=("$1")
                    parsing_files=true
                else
                    if [ -z "$user_question" ]; then
                        user_question="$1"
                    else
                        user_question="$user_question $1"
                    fi
                fi
                shift
                ;;
        esac
    done

    if [ ${#files[@]} -eq 0 ]; then
        echo "❌ 错误: 请提供至少一个图片文件"
        show_help
    fi

    if [ -z "${user_question:-}" ]; then
        if [ -t 0 ]; then
            warn "❌ 没有提供任何 prompt 输入"
            exit 1
        else
            user_question=$(cat)
        fi  
    fi

    if [ -z "$user_question" ]; then
        user_question="这些图片是什么内容？请详细描述。"
    fi

    echo "🤖 使用模型: $model_name"
    echo "📝 用户问题: $user_question"
    upload_files "${files[@]}"
}



# 在main函数开始时添加缓存清理
main() {
    #if [ -z "$DASHSCOPE_API_KEY" ]; then
    #    echo "❌ 错误: 请设置 DASHSCOPE_API_KEY 环境变量"
    #    exit 1
    #fi

    DASHSCOPE_API_KEY=$(jq -r '.api_key' "$APIKEY_JSON"|base64 --decode)

    # 清理过期缓存
    cleanup_cache

    if [ $# -eq 0 ]; then
        show_help
    fi

    get_upload_policy
    parse_args "$@"
    call_model_api
}

# 执行主函数
main "$@"
