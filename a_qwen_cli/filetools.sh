#!/bin/bash

# 获取缓存的URL
get_cached_url() {
    local file_hash="$1"
    local file_size="$2"
    local current_time=$(date +%s)

    if [ ! -f "$CACHE_FILE" ]; then
        echo "{}" > "$CACHE_FILE"
        return 1
    fi

    local cached_data=$(jq -r --arg hash "$file_hash" --arg size "$file_size" \
        '.[$hash] | select(.size == $size and (.timestamp + 1728000000) > now)' \
        --argjson now "$current_time" "$CACHE_FILE")

    if [ -n "$cached_data" ]; then
        echo "$cached_data" | jq -r '.id'
        return 0
    fi
    return 1
}

# 更新缓存
update_cache() {
    local file_hash="$1"
    local file_size="$2"
    local file_id="$3"
    local current_time=$(date +%s)

    local new_entry="{\"id\": \"$file_id\", \"size\": \"$file_size\", \"timestamp\": $current_time}"

    if [ -f "$CACHE_FILE" ]; then
        jq --arg hash "$file_hash" --arg entry "$new_entry" \
            'del(.[] | select(.timestamp + 1728000000 < now)) * . + {($hash): ($entry|fromjson)}' \
            --argjson now "$current_time" "$CACHE_FILE" > "${CACHE_FILE}.tmp" && \
        mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    else
        echo "{\"$file_hash\": $new_entry}" > "$CACHE_FILE"
    fi
}

upload_single_file() {
    local file="$1"
    local dryrun="${2:-}"

    local filename=$(basename "$file")
    local file_hash=$(calculate_xxhash "$file")
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")

    debug "📎 开始上传: $filename"

    # 检查缓存
    local cached_id=$(get_cached_url "$file_hash" "$file_size")
    if [ -n "$cached_id" ]; then
        debug "✅ 使用缓存的文件: $filename"
        returnd "$cached_id" "usecached"
        return 0
    fi

    if [ -n "$dryrun" ]; then
        debug "🟡 Dry run: $filename"
        returnd "dryrun" "dryrun"
        return 0
    fi


    # 使用 curl 上传并记录速度信息
    local response=$(curl -X POST \
        -H "Authorization: Bearer $DASHSCOPE_API_KEY" \
        -H "Content-Type: multipart/form-data" \
        -F "file=@$file" \
        -F "purpose=file-extract" \
        "${API_BASE_URL}/files")
     

    local file_id=$(echo "$response" | jq -r '.id')
    if [ -n "$file_id" ] && [ "$file_id" != "null" ]; then
        update_cache "$file_hash" "$file_size" "$file_id"

        debug "✅ 上传成功: $filename "
        returnd "$file_id" "uploadok"
        return 0
    else
        debug "❌ 上传成功但未获取到 file_id: $filename"
        debug "响应内容: $response"
        return 1
    fi
}



upload_files() {
    local file_array_t=$1  #传入的json数组
    local dryrun="${2:-}"
    
    # warn "dry run: $dryrun"

    local success_count=0
    local failed_count=0
    local cached_count=0
    
    local f_json=$(jq -n '{ files: [] }')  # 创建json
    
    info "对话文件的清单为: $file_array_t"
    
    local filename=""
    while IFS= read -r file_path; do
        #filename=$(jq -r . <<< "$file_path")
        filename=$(jq -r . <<< "$file_path") || filename=""
        
        if [[ -z "${filename:-}" ]]; then
        warn "警告: 文件名为空"
        continue
        fi
      
        debug "上传文件111111: $filename 2222222"

        if [[ ! -f "${filename:-}" ]]; then
        error "错误: 文件 '$filename' 不存在"
        ((failed_count++))
        continue
        fi

        #local filename=$file_path
        debug "上传文件111: $file_path"
	if [[ $dryrun ]]; then
        	local response=$(upload_single_file "$filename" "dryrun")
        else
		local response=$(upload_single_file "$filename")
        	debug "respon:  $response"
	fi
        if [[ $response == '{"error'* ]]; then
            error "文件 $filename 上传错误 $response"
            ((failed_count++))
        elif [[ $(jqd "$response" "status") == "usecached" ]]; then
            info "文件 $filename 已存在，没有上传,直接引用"
            local new_id=$(jqd "$response")
            f_json=$(add_file_to_json "$f_json" "$new_id" "$filename")
            ((cached_count++))
        elif [[ $(jqd "$response" "status") == "uploadok" ]]; then
            info "上传成功: $filename"
            local new_id=$(jqd "$response")
            f_json=$(add_file_to_json "$f_json" "$new_id" "$filename")
            ((success_count++))
        elif [[ $(jqd "$response" "status") == "dryrun" ]]; then
             info "dryrun 实际未上传: $filename"
             #local new_id=$(jqd "$response")
             #f_json=$(add_file_to_json "$f_json" "$new_id" "$filename")
             #((success_count++))
	else
            debug "未知数"
        fi
    done < <(jq -c '.[]' <<< "$file_array_t") #输入文件列表
  
    info "上传完成：成功 $success_count 个，引用 $cached_count 个，失败 $failed_count 个"
  
    jq -c '.status="ok"' <<< $f_json
    return 0
}



cleanup_orphaned_files() {
    # 清理完成之后的本地缓存是不是要重建？？整个逻辑还是不清
    # 比如，

    local files_json="$1"
    debug "filejson: ${files_json}"

    # 获取服务器文件列表
    local server_response=$(curl -sS --max-time 30 -X GET "$API_BASE_URL/files" \
        -H "Authorization: Bearer $DASHSCOPE_API_KEY")
    
    if ! validate_json "$server_response"; then
        error "❌ 获取服务器文件列表失败"
        return 1
    fi 
    
    # 获取本地文件ID列表
    # local local_ids=($(get_local_file_ids "$files_json"))
    local local_ids=$(jq -r 'map(.id)' <<< "$files_json")
    debug "localids: ${local_ids}"
    # 找出需要删除的文件
    #local orphaned_files=$(echo "$server_response" | jq -r --arg ids "${local_ids[*]}" '
    #    .data[] | select(.id as $fid | ($ids | split(" ")) | index($fid) | not) | 
    #    {id: .id, filename: .filename}
    #')

    local orphaned_files=$(echo "$server_response" | jq -c --argjson ids "$local_ids" '
    .data[] 
    | select(.id as $fid | $ids | index($fid) | not)
    | {id: .id, filename: .filename}'
    )
    
    if [ -z "$orphaned_files" ]; then
        info "没有发现需要清理的文件"
        return 0
    fi
    
    echo "发现以下孤立文件："
    echo "$orphaned_files" | jq -r '["文件ID", "文件名"], [.id, .filename] | @tsv' | column -t -s $'\t'
    echo "$orphaned_files" > oo.out 
    read -p "是否删除这些文件？(y/n): " -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$orphaned_files" | jq -c '.' | while read -r file; do
            local file_id=$(echo "$file" | jq -r '.id')
            local filename=$(echo "$file" | jq -r '.filename')
            echo -n "正在删除 $filename... "
            
            local response=$(curl -sS --max-time 30 -X DELETE "$API_BASE_URL/files/$file_id" \
                -H "Authorization: Bearer $DASHSCOPE_API_KEY")
            
            if validate_json "$response" && jq -e '.deleted' <<<"$response" &>/dev/null; then
                echo "成功"
            else
                echo "失败: $(jq -r '.error.message // "未知错误"' <<<"$response")"
            fi
        done
    else
        echo "取消清理操作"
    fi
    
    local clean_ids=$(jq -r 'map(.id)' <<< "$orphaned_files")

    delete_cache_by_ids "$clean_ids"

    
}


delete_files_by_json_ids() {
    local ids_json="$1"

    # 检查是否是合法 JSON 数组
    if ! jq -e . >/dev/null 2>&1 <<< "$ids_json"; then
        debug "❌ 输入不是合法的 JSON 数组"
        return 1
    fi

    # 提取 clean_ids
    local clean_ids=$(jq -r 'map(sub("fileid://"; ""))' <<< "$ids_json")
    local num_ids=$(jq length <<< "$clean_ids")

    [ "$num_ids" -eq 0 ] && debug "❌ 没有要删除的文件 ID" && return 1

    local failed_count=0

    while IFS= read -r file_id; do
        debug "🗑️ 正在删除远程文件: $file_id"
        local status=$(curl -sS -w "%{http_code}" -X DELETE "$API_BASE_URL/files/$file_id" \
            -H "Authorization: Bearer $DASHSCOPE_API_KEY" -o /dev/null)

        if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
            debug "✅ 成功删除: $file_id"
        else
            debug "❌ 删除失败 (HTTP %d): %s" "$status" "$file_id"
            ((failed_count++))
        fi
    done < <(jq -c '.[]' <<< "$clean_ids")

    delete_cache_by_ids "$clean_ids"

    debug "✅ 已尝试删除 %d 个文件，其中 %d 个失败" "$num_ids" "$failed_count"
}

# 删除缓存中指定 id 的条目（输入为 JSON 数组）
delete_cache_by_ids() {
    local ids_json="$1"

    # 检查是否是合法 JSON 数组
    if ! jq -e . >/dev/null 2>&1 <<< "$ids_json"; then
        error "❌ 输入不是合法的 JSON 数组"
        return 1
    fi

    # 确保缓存文件存在
    if [ ! -f "$CACHE_FILE" ]; then
        error "❌ 缓存文件不存在"
        return 1
    fi

    # 使用 jq 删除缓存中 id 在列表中的条目
    jq --argjson ids "$ids_json" '
        del( .[] | select(.id | IN($ids[]) )
    ' "$CACHE_FILE" > "${CACHE_FILE}.tmp" && \
    mv "${CACHE_FILE}.tmp" "$CACHE_FILE"

    info "✅ 已删除 $(jq length <<< "$ids_json") 个缓存条目"
}

# 删除指定天数前的缓存条目
delete_cache_by_time() {
    local days="$1"
    local current_time=$(date +%s)
    local expire_time=$((current_time - days * 86400))

    if [ ! -f "$CACHE_FILE" ]; then
        error "❌ 缓存文件不存在"
        return 1
    fi

    jq --argjson now "$expire_time" 'del(.[] | select(.timestamp < $now))' "$CACHE_FILE" > "${CACHE_FILE}.tmp" && \
    mv "${CACHE_FILE}.tmp" "$CACHE_FILE"

    info "✅ 已删除 $days 天前的缓存条目"
}
