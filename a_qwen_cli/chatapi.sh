#!/usr/bin/env bash


get_endpoint_by_model() {
# 请注意:此处endpoint参数值需和输入文件中的url字段保持一致.
# 测试模型(batch-test-model)填写/v1/chat/ds-test
# Embedding文本向量模型填写/v1/embeddings
# 其他模型填写/v1/chat/completions

local model="$1"

if [[ $model == batch-test-model ]]; then
	echo "/v1/chat/ds-test"
elif [[ $model == text-embedding* ]]; then
	echo "/v1/embeddings"
elif [[ $model == qwen* ]]; then
	echo "/v1/chat/completions"
else
    error "bad model name..."
    exit 1
fi

} 


timestamp_to_date() {
    local timestamp="$1"
    local adjusted_timestamp=$((timestamp + 8 * 3600))  # 北京时间 (UTC+8)
    
    if date --version >/dev/null 2>&1; then  # GNU date (Linux)
        date -u -d "@$adjusted_timestamp" +"%Y-%m-%d %H:%M:%S"
    else  # BSD/macOS date
        date -u -r "$adjusted_timestamp" +"%Y-%m-%d %H:%M:%S"
    fi
}


process_stream_line() {
    local line="$1"
    local json_line="${line#data: }"
    local cost=0.0001 

    #echo $line

    [ "$json_line" == "[DONE]" ] && return 0

    if [[ $line == {\"error\":* ]]; then
        handle_error_response "$line"
        return 1
    fi

    # 使用单个 jq 查询处理所有情况
    local jq_output
    jq_output=$(jq -r '
        if .usage then
            "USAGE:" + (.model|tostring) + "|" + 
            (.usage.prompt_tokens|tostring) + "|" + 
            (.usage.completion_tokens|tostring) + "|" + 
            (.usage.total_tokens|tostring) + "|" + 
            ((.usage.prompt_tokens_details.cached_tokens // 0)|tostring) + "|" + 
            (.created|tostring)
        elif .choices[0].delta.content then
            "CONTENT:" + (.choices[0].delta.content // "")
        else
            empty
        end
    ' <<< "$json_line" 2>/dev/null)

    # 处理 usage 情况
    if [[ "$jq_output" == USAGE:* ]]; then
        IFS='|' read -r model prompt_tokens completion_tokens total_tokens cached_tokens created <<< "${jq_output#USAGE:}"
        
        # 转换时间戳为可读格式
        local readable_time=$(timestamp_to_date "$created")

# 先计算 cost
cost=$(awk -v prompt="$prompt_tokens" -v completion="$completion_tokens" \
    'BEGIN {
        cost = prompt * 0.0000005 + completion * 0.000002;
        printf "%.4f", cost
    }')

echo -e "\n"
info  "输出完成，以下为统计信息。"

# 输出固定格式的内容
cat <<EOF

模型: $model
用户输入: $prompt_tokens 个 tokens（其中缓存 $cached_tokens 个）
模型输出: $completion_tokens 个 tokens
总计: $total_tokens 个 tokens
估算费用：$cost 元
创建时间: $readable_time
EOF


        return 0
    fi

    # 处理内容情况
    if [[ "$jq_output" == CONTENT:* ]]; then
        printf "%s" "${jq_output#CONTENT:}"
    fi

    return 0
}


# 处理原始响应
process_raw_response() {
    # 传入两个参数
    local response_content="$1"
    local json_data="$2"
    debug "原始响应内容：$response_content eee" >&2
    debug "JSON 数据：$json_data eee2" >&2
    # 构建响应 JSON

    
    local response_json=$(jq -n \
        --arg content "$response_content" \
        '{
            choices: [{
                message: {
                    role: "assistant",
                    content: $content
                }
            }]
        }') || { error "❌ 响应JSON构造失败"; return 1; }

    # 将请求和响应合并为一个 JSON
    local merged_json=$(jq -n \
        --argjson request "$json_data" \
        --argjson response "$response_json" \
        '{
            request: $request,
            response: $response
        }') || { error "❌ JSON 合并失败"; return 1; }


    # 构造响应文件
    local response_file="${LOG_DIR}/api_response_$(date +%s).json"
    > "$response_file"  # 清空文件    # 构造响应文件

    # 写入合并后的内容
    echo "$merged_json" > "$response_file"
    echo -e "\n\n响应已保存到: $response_file"

    exec bash "$SCRIPT_DIR/json2md.sh" "$response_file" "$MARKDOWN_PATH"

    
    return 0
}

# 调用 API
call_api() {
    local json_data="$1"
    
    local model="$2"
    local files_json="${3:-}"



    debug "zzzzzz01: ${json_data[@]}"
    local model_config=$(jq --arg model "$model" 'getpath([$model])' <<< "$MODEL_CONFIG")
    if [ "$(echo "$model_config" | jq -r '.override' || true)" = "1" ]; then
        local params=$(echo "$model_config" | jq -r '.params')
        if [ -n "$params" ]; then
            json_data=$(jq --argjson params "$params" '. += $params' <<< "$json_data")
        fi
    fi

    # 使用临时文件存储原始响应
    #local raw_response="${LOG_DIR}/raw_response_$(date +%s).txt"
    #> "$raw_response"
    
    #local post_json_data=$(echo "$json_data" | jq -c '.messages |= unique_by(.content)')
    #除虫，并不影响排序
    #local post_json_data=$(jq -c '
    #.messages |= (
    #    . as $original | 
    #    unique_by(.content) |
    #    sort_by(
    #    . as $item |
    #    ($original | index($item))
    #    )
    #)
    #' <<< "$json_data")

    info "INFO: Post JSON Data:"
    echo "$json_data" | jq . >&2

    info "Calling API..."

    local curl_exit_code
    local response_content=""

    # 使用命名管道处理流式响应（纯内存操作）
    exec 3< <(
        stdbuf -oL curl -sS -X POST "$API_BASE_URL/chat/completions" \
            -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$json_data" 2> "${LOG_DIR}/curl_error.log"
        echo "CURL_EXIT_CODE:$?" 
    )

    while IFS= read -r line <&3; do
        # 检查是否是curl退出码
        if [[ "$line" == "CURL_EXIT_CODE:"* ]]; then
            curl_exit_code="${line#CURL_EXIT_CODE:}"
            break
        fi
        
        # 只在终端显示，不写入文件
        #echo "$line"
        
        # 检查错误信息
        if [[ "$line" == '{"error"'* ]]; then
            error "API error detected: $line"
            exec 3<&-
            return 1
        fi
        
        response_content+=$(process_stream_line "$line" | tee /dev/tty)
    done

    exec 3<&-

    # 检查curl退出码
    if [[ "$curl_exit_code" != "0" ]]; then
        error "Curl failed with exit code: $curl_exit_code"
        return 1
    fi

    info "API call completed."


    # 直接调用 curl 并捕获原始响应
    
    #info "Calling API..."

    #while IFS= read -r -d '' line; do
    #    echo "$line"
    #    response_content+=$(process_stream_line "$line"|tee /dev/tty)
    #done < <(stdbuf -oL curl -sS -X POST "$API_BASE_URL/chat/completions" \
    #-H "Authorization: Bearer $DASHSCOPE_API_KEY" \
    #-H "Content-Type: application/json" \
    #-d "$json_data" 2> "${LOG_DIR}/curl_error.log")
    #-d @- <<< "$json_data")      
    #info "API call completed."
    
    # 处理响应
    # [ -n "$files_json" ] && json_data=$(jq --argjson files "$files_json" '. += {files: ($files | unique_by(.id))}' <<< "$json_data") 
    [ -n "$files_json" ] && json_data=$(jq --argjson files "$files_json" '. += {files: ($files )}' <<< "$json_data") 

    process_raw_response "$response_content" "$json_data"
}

# 错误处理函数
handle_error_response() {
    local error_json="$1"
    local request_json="${2:-}"
    local response_file="${3:-}"
    
    local error_message=$(echo "$error_json" | jq -r '.error.message')
    error "❌ 错误: $error_message"
    error "DEBUG: 完整错误信息: $error_json"

    # 构建错误响应 JSON
    local error_response_json=$(jq -n \
        --argjson request "$request_json" \
        --argjson error "$error_json" \
        '{
            request: $request,
            response: {
                error: $error
            }
        }') || { error "❌ 错误响应JSON构造失败"; return 1; }

    # 写入合并后的内容
    echo "$error_response_json" > "$response_file"

    echo -e "\n\n错误响应已保存到: $response_file"
    return 1
}


# 与文件对话
chat_with_files() {
    local file_paths_t=$1
    local user_question=$2
    local model_name=$3
    local dry_run=${4:-}

    debug "998: $file_paths_t 990"

    local file_ids_t=$(upload_files "$file_paths_t")
    debug "file_ids_t: ${file_ids_t}"


    [ "$user_question" = "q" ] && return 0
    [ -z "$user_question" ] && {
        error "错误: 问题不能为空"
        continue
    }

    local messages_json=$(jq -n \
    --arg msg "$user_question" \
    --arg model "$model_name" \
    --argjson input_json "$file_ids_t" '
    {
        model: $model ,
        messages: ([
        { role: "system", content: "You are a helpful assistant." }
        ] + [
        $input_json.files[] | { role: "system", content: ("fileid://" + .id) }
        ] + [
        { role: "user", content: $msg }
        ]),
        stream: true,
        stream_options: { include_usage: true }
    }
    ')

        debug "yyyyy011: ${messages_json}"
        # 构造 files 数组
        local files_json=$(jq '.files' <<< "$file_ids_t")
        debug "yyyyy01: ${files_json}"
        # 调用 call_api，这里要调整为api返回，增加一段再保存，call_api不应该干这个事
        #r_path=$(call_api "$messages_json" "$model_name") #"$files_json"
        #process_raw_response "$r_path" "$files_json" 

        local post_json_data=$(jq -c '
            .messages |= (
            . as $original | 
            unique_by(.content) |
            sort_by(
            . as $item |
            ($original | index($item))
            )
        )
        ' <<< "$messages_json")

        local model_config=$(jq --arg model "$model_name" 'getpath([$model])' <<< "$MODEL_CONFIG")
        if [ "$(echo "$model_config" | jq -r '.override' || true)" = "1" ]; then
            local params=$(echo "$model_config" | jq -r '.params')
        
            if [ -n "$params" ]; then
            post_json_data=$(jq --argjson params "$params" '. += $params' <<< "$post_json_data")
            fi  
        
        fi

        if [[ $dry_run == "dryrun_files" ]]; then
            debug "dry_run: $files_json"
            echo "$files_json"
            #jq -r '.' <<< "${files_json}"a
        elif [[ $dry_run == "dryrun_messages" ]]; then
            debug "dry_run messages: $post_json_data"
            echo "$post_json_data"
        else
            debug "nothing call: $dry_run"
            #exit 1
            call_api "$post_json_data" "$model_name" "$files_json"
        fi


}

