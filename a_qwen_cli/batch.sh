#!/bin/bash


# 构造单个 batch 请求条目
construct_batch_item() {
    local custom_id="$1"
    local url="$2"
    #local model="$3"
    local body="$3"

    #jq -c --arg id "$custom_id" --arg url "$url" --argjson body "$body" '
    #{
    #  custom_id: $id,
    #  method: "POST",
    #  url: $url,
    #  body: $body
    #}' <<< "{}"

    jq -c --arg id "$custom_id" --arg url "$url" '
    {
      custom_id: $id,
      method: "POST",
      url: $url,
      body: (
        . 
        | del(.stream, .stream_options)
      )
    }' <<< "$body"

}

# 获取下一个 custom_id
get_next_custom_id() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo "1"
    else
        tail -n 1 "$file" | jq -r .custom_id | awk '{print $1 + 1}'
    fi
}

: '
if [ -n "$batch_file" ]; then
    next_id=$(get_next_custom_id "$batch_file")

    item=$(construct_batch_item "$next_id" "$url" "$batch_model" "$messages_json")

    echo "$item" >> "$batch_file"
    echo "✅ 已添加请求至 batch 文件: $batch_file"
else
    # 非 batch 模式下直接调用 API
    response=$(curl -sS -X POST "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"  \
        -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$messages_json")

    echo "$response" | jq .
fi
'

# 1. 上传文件
upload_batch_file() {
    local FILE_PATH="$1"
    echo "🔄 正在上传文件: $FILE_PATH" >&2
    local UPLOAD_RESPONSE=$(curl -s -X POST "https://dashscope.aliyuncs.com/compatible-mode/v1/files" \
        -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
        --form "file=@$FILE_PATH" \
        --form "purpose=batch")

    local FILE_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.id')

    if [ -z "$FILE_ID" ] || [ "$FILE_ID" = "null" ]; then
        echo "❌ 文件上传失败" >&2
        echo "Response: $UPLOAD_RESPONSE" >&2
        exit 1
    fi

    echo "✅ 文件上传成功，file_id: $FILE_ID" >&2
    echo "$FILE_ID"
}

# 2. 创建 Batch 任务
# 请注意:此处endpoint参数值需和输入文件中的url字段保持一致.
# 测试模型(batch-test-model)填写/v1/chat/ds-test
# Embedding文本向量模型填写/v1/embeddings
# 其他模型填写/v1/chat/completions

create_batch_job() {
    local input_file_id="$1"
    local endpoint="$2"
    echo "🔄 正在创建 Batch 任务，使用文件 ID: $input_file_id" >&2

    local json_data=$(jq -n \
  --arg input_file_id "$input_file_id" \
  --arg endpoint "$endpoint" \
  '{
    input_file_id: $input_file_id,
    endpoint: $endpoint,
    completion_window: "24h",
    metadata: {
      ds_name: "MyBatchTask",
      ds_description: "Test Batch Task"
    }
  }')

local CREATE_RESPONSE=$(curl -s -X POST "https://dashscope.aliyuncs.com/compatible-mode/v1/batches"  \
    -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$json_data")

    local BATCH_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')

    if [ -z "$BATCH_ID" ] || [ "$BATCH_ID" = "null" ]; then
        echo "❌ 创建 Batch 任务失败" >&2
        echo "Response: $CREATE_RESPONSE" >&2
        exit 1
    fi

    echo "✅ Batch 任务创建成功，batch_id: $BATCH_ID" >&2
    echo "$BATCH_ID"
}

# 3. 轮询任务状态
poll_job_status_once() {
    local batch_id="$1"
    echo "正在询任务状态: $batch_id" >&2

    local STATUS=$(curl -s -X GET "https://dashscope.aliyuncs.com/compatible-mode/v1/batches/$batch_id" \
        -H "Authorization: Bearer $DASHSCOPE_API_KEY" | jq -r '.status')
    sleep 10
    
    echo "📊 当前状态: $STATUS" >&2
    echo "$STATUS"
}

poll_job_status() {
    local batch_id="$1"
    local run_count="${2:-}"
    local start=0

    echo "🔄 正在轮询任务状态: $batch_id" >&2
    #while true; do
    while [[ -z "$run_count" || "$start" -lt "$run_count" ]]; do
        local STATUS=$(poll_job_status_once "$batch_id")
        if [ "$STATUS" = "completed" ]; then
            echo "✅ 任务完成" >&2
            break
        elif [ "$STATUS" = "failed" ]; then
            echo "❌ 任务失败" >&2
            echo "获取错误信息..." >&2
            local ERROR_DETAILS=$(curl -s -X GET "https://dashscope.aliyuncs.com/compatible-mode/v1/batches/$batch_id" \
                -H "Authorization: Bearer $DASHSCOPE_API_KEY" | jq .)
            echo "Error Details: $ERROR_DETAILS" >&2
            exit 1
        elif [ "$STATUS" = "expired" ] || [ "$STATUS" = "cancelled" ]; then
            echo "❌ 任务已过期或取消" >&2
            exit 1
        fi
        
        start=$((start + 1))
        sleep 1  # 避免过于频繁请求，建议加上间隔时间

    done

    # 如果是因为达到 run_count 而退出
    if [[ "$start" -eq "$run_count" ]]; then
        echo "⚠️ 已达到最大尝试次数 ($run_count)，未等到任务完成。" >&2
        # exit 1
    fi
    
    # 返回
    echo "$STATUS"

}

# 4. 获取输出文件 ID
get_output_file_id() {
    local batch_id="$1"
    echo "🔄 正在获取输出文件 ID for 任务: $batch_id" >&2
    local OUTPUT_FILE_ID=$(curl -s -X GET "https://dashscope.aliyuncs.com/compatible-mode/v1/batches/$batch_id" \
        -H "Authorization: Bearer $DASHSCOPE_API_KEY" | jq -r '.output_file_id' )

    if [ -z "$OUTPUT_FILE_ID" ] || [ "$OUTPUT_FILE_ID" = "null" ]; then
        echo "❌ 未找到输出文件" >&2
        exit 1  
    fi
    echo "📄 输出文件 ID: $OUTPUT_FILE_ID" >&2
    echo >&2
    echo "$OUTPUT_FILE_ID"
}


download_results() {
    local output_file_id="$1"
    local output_file_path="$2"

    # 调试输出
    echo "📥 开始下载文件 ID: $output_file_id" >&2
    if [ -z "$output_file_id" ]; then
        echo "❌ 错误：output_file_id 为空"
        exit 1
    fi

    # URL 编码（可选）
    local url="https://dashscope.aliyuncs.com/compatible-mode/v1/files/${output_file_id}/content" 

    echo "🌐 请求地址: $url" >&2
    curl -s -X GET "$url" \
        -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
        -o $output_file_path

    # 检查文件是否为空
    if [ ! -s "$output_file_path" ]; then
        echo "❌ 下载结果为空，请检查 API 返回或权限设置" >&2
        exit 1
    else
        echo "✅ 文件已保存到 $output_file_path" >&2
    fi
}


run_batch() { 

    local batch_file="$1"
    local run_batch_file="$batch_file.run"
# testing run
    # jq -n '{}'
    local json=$(jq -n --arg bfile1 "$batch_file" '{"batch_file": $bfile1}')

    file_id=$(upload_batch_file "$1")
    
    json=$(jq --arg fid1 "$file_id" '.input_file_id=$fid1' <<< "$json")

    batch_id=$(create_batch_job "$file_id" "/v1/chat/completions")

    json=$(jq --arg bid1 "$batch_id" '.batch_id=$bid1' <<< "$json")

    echo "$json" > "$run_batch_file"
    echo "✅ 运行文件已保存到 $run_batch_file" >&2
    echo "Running batch job..."    
}

output_batch() {
    # 本函数可以放在crontab中去跑
    local batch_file="$1"
    local run_batch_file="$batch_file.run"
    local output_batch_file="$batch_file.output"
    local done_batch_file="$run_batch_file.done"

    if [ -f "$done_batch_file" ]; then
        echo "该runbatch已经done，不需要执行，退出..." >&2
        exit 1
    fi

    if [ ! -f "$run_batch_file" ]; then
        echo "❌ 运行文件不存在" >&2
        exit 1
    fi

    if ! jq -e '.batch_id' "$run_batch_file" >/dev/null 2>&1; then
        echo "❌ 运行文件格式错误" >&2
        exit 1
    fi

    local output_file="output_$batch_file"

    local batch_id=$(jq -r '.batch_id' "$run_batch_file")

    # 执行5次查询
    local job_status=$(poll_job_status "$batch_id" 5)

    if [ "$job_status" != "completed" ]; then
        echo "❌ 任务未完成" >&2
        exit 1
    fi
    
    local output_file_id=$(get_output_file_id "$batch_id")

    sleep 5

    download_results "$output_file_id" "$output_batch_file"

    # 改名，下次运行时不执行
    mv "$run_batch_file" "$run_batch_file.done"

}

# testing run
#file_id=$(upload_file "$1")
#batch_id=$(create_batch_job "$file_id")
#poll_job_status "$batch_id"
#output_file_id=$(get_output_file_id "$batch_id")
#sleep 5
#download_results "$output_file_id"


