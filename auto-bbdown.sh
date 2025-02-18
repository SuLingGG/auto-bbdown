#!/bin/bash

# 载入配置文件
source ./config/auto-bbdown.config

# 创建日志目录
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bbdown_$(date +%Y-%m-%d).log"

# 重定向标准输出和标准错误到日志文件，同时过滤掉特定的日志内容
exec > >(tee -a "$LOG_FILE" | grep -avE 'version|查阅|nilaoda|^[[:space:]]*$') 2>&1

# 获取当前时间戳
get_timestamp() {
    echo "$(date +"[%Y-%m-%d %H:%M:%S.%3N]")"
}

# 发送消息函数
MSG() {
    local MESSAGE="$1"
    local MSG_TYPE="DEBUG"
    local EDIT_MODE="new"
    local TIMESTAMP=$(get_timestamp)

    if [[ "$MESSAGE" == *"[INFO]"* ]]; then
        MSG_TYPE="INFO"
        MESSAGE=${MESSAGE//\[INFO\]/}
    elif [[ "$MESSAGE" == *"[DEBUG]"* ]]; then
        MSG_TYPE="DEBUG"
        MESSAGE=${MESSAGE//\[DEBUG\]/}
    fi

    if [[ "$MESSAGE" == *"[EDIT_BEFORE]"* ]]; then
        EDIT_MODE="before"
        MESSAGE=${MESSAGE//\[EDIT_BEFORE\]/}
    elif [[ "$MESSAGE" == *"[EDIT_AFTER]"* ]]; then
        EDIT_MODE="after"
        MESSAGE=${MESSAGE//\[EDIT_AFTER\]/}
    fi

    local FULL_MSG="${TIMESTAMP} - ${MESSAGE}"
    local CLEAN_MSG=$(echo "$FULL_MSG" | sed -E 's/\[.*\]//g')

    if { [ "$MSG_TYPE" = "INFO" ] || [ "$LOG_MSG_DEBUG" = "true" ]; }; then
        echo "$FULL_MSG"
    fi

    if [ "$ENABLE_TG_MSG" = "true" ]; then
        if { [ "$MSG_TYPE" = "INFO" ] || { [ "$MSG_TYPE" = "DEBUG" ] && [ "$TG_MSG_DEBUG" = "true" ]; }; }; then
            case $EDIT_MODE in
                "before")
                    local RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                        -d chat_id="${CHAT_ID}" \
                        -d text="${FULL_MSG}")
                    local MSG_ID=$(echo "$RESPONSE" | jq -r '.result.message_id')
                    [ -n "$MSG_ID" ] && echo "$MSG_ID" > "$MSG_ID_FILE"
                    ;;
                "after")
                    if [ -f "$MSG_ID_FILE" ]; then
                        local MSG_ID=$(cat "$MSG_ID_FILE")
                        curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/editMessageText" \
                            -d chat_id="${CHAT_ID}" \
                            -d message_id="${MSG_ID}" \
                            -d text="${FULL_MSG}" >/dev/null
                        rm -f "$MSG_ID_FILE"
                    fi
                    ;;
                *)
                    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                        -d chat_id="${CHAT_ID}" \
                        -d text="${FULL_MSG}" >/dev/null
                    ;;
            esac
        fi
    fi
}

# 错误日志函数
FAILED_LOGS() {
    mkdir -p "$LOG_DIR/failed-logs"
    FAILED_DYNAMIC_DATA=$(cat "$DYNAMIC_DATA")
    FAILED_LOG_FILE="$LOG_DIR/failed-logs/$(date +"[%Y-%m-%d %H:%M:%S.%3N]").log"
    {
        echo "DOWNLOAD_MODE:"; echo "$DOWNLOAD_MODE"; echo
        echo "BVID:"; echo "$BVID"; echo
        echo "FAILED_DYNAMIC_DATA:"; echo "$FAILED_DYNAMIC_DATA"; echo
        echo "DATA:"; echo "$DATA"; echo
        echo "DYNAMIC_RESPONSE:"; echo "$DYNAMIC_RESPONSE"; echo
        echo "NEW_DYNAMIC_DATA:"; echo "$NEW_DYNAMIC_DATA"; echo
        echo "CHANGE_VIDEO_DATA:"; echo "$CHANGE_VIDEO_DATA"; echo
        echo "FILTERED_DATA:"; echo "$FILTERED_DATA"
    } > "$FAILED_LOG_FILE"
}

# 锁文件函数
CREATE_LOCK() {
    if [ -f "$LOCK_FILE" ]; then
        MSG "[DEBUG]另一个实例正在运行，退出..."
        exit 1
    fi
    touch "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; exit' SIGINT SIGTERM EXIT
}

# 调用创建锁文件函数
CREATE_LOCK

# 获取动态响应数据
DYNAMIC_RESPONSE=$(curl -s 'https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all?timezone_offset=-480&type=video&platform=web&page=1&features=itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete,onlyfansQaCard,commentsNewVersion&web_location=0.0&x-bili-device-req-json=%7B%22platform%22:%22web%22,%22device%22:%22pc%22%7D&x-bili-web-req-json=%7B%22spm_id%22:%220.0%22%7D' \
    -H 'accept: */*' \
    -H 'accept-language: zh-CN,zh;q=0.9,zh-TW;q=0.8' \
    -H 'cache-control: no-cache' \
    -H "cookie: $COOKIE" \
    -H 'pragma: no-cache' \
    -H 'priority: u=1, i' \
    -H 'referer: https://t.bilibili.com/?tab=video' \
    -H 'sec-ch-ua: "Not(A:Brand";v="99", "Google Chrome";v="133", "Chromium";v="133"' \
    -H 'sec-ch-ua-mobile: ?0' \
    -H 'sec-ch-ua-platform: "Linux"' \
    -H 'sec-fetch-dest: empty' \
    -H 'sec-fetch-mode: cors' \
    -H 'sec-fetch-site: same-site' \
    -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36')

# 检查动态数据文件是否存在，不存在则下载第一个视频
if [ ! -f "$DYNAMIC_DATA" ]; then
    NEW_DYNAMIC_DATA=$(echo "$DYNAMIC_RESPONSE" | jq '[.data.items[] | select(.modules.module_dynamic.major.type == "MAJOR_TYPE_ARCHIVE") | {name: .modules.module_author.name, title: .modules.module_dynamic.major.archive.title, bvid: .modules.module_dynamic.major.archive.bvid, mid: .modules.module_author.mid}]')
    
    case "$DOWNLOAD_MODE" in
        "all")
            FIRST_BVID=$(echo "$NEW_DYNAMIC_DATA" | jq -r '.[0].bvid')
            NAME=$(echo "$NEW_DYNAMIC_DATA" | jq -r '.[0].name')
            TITLE=$(echo "$NEW_DYNAMIC_DATA" | jq -r '.[0].title')
            
            MSG "[INFO][EDIT_BEFORE]首次运行，正在下载 ${NAME} 的稿件「${TITLE}」(${FIRST_BVID})..."
            
            cd "$ROOT_DOWNLOAD_DIR" || exit 1
            if [ "$ENABLE_BBDOWN_LOG" = "true" ]; then
                $BBDOWN "https://www.bilibili.com/video/$FIRST_BVID"
            else
                $BBDOWN "https://www.bilibili.com/video/$FIRST_BVID" >/dev/null 2>&1
            fi
            BBDOWN_EXIT_CODE=$?
            
            if [ $BBDOWN_EXIT_CODE -eq 0 ]; then
                MSG "[INFO][EDIT_AFTER]首次运行，已下载 ${NAME} 的稿件「${TITLE}」(${FIRST_BVID})。"
            else
                MSG "[INFO][EDIT_AFTER]稿件下载失败。%0A调试信息:%0AFIRST_BVID:${FIRST_BVID}%0ANAME:%0A${NAME}%0ATITLE:%0A${TITLE}%0ANEW_DYNAMIC_DATA:%0A${NEW_DYNAMIC_DATA}"
                FAILED_LOGS
            fi
            ;;
            
        "black"|"white")
            MODE_NAME=$([ "$DOWNLOAD_MODE" = "black" ] && echo "黑名单" || echo "白名单")
            MSG "[INFO]检测到脚本第一次运行，由于已定义下载${MODE_NAME}，脚本将在后续运行过程中检测并下载新增视频。"
            ;;
    esac
    
    echo "$NEW_DYNAMIC_DATA" > "$DYNAMIC_DATA"
    exit 0
fi

# 解析新的动态数据
NEW_DYNAMIC_DATA=$(echo "$DYNAMIC_RESPONSE" | jq '[.data.items[] | select(.modules.module_dynamic.major.type == "MAJOR_TYPE_ARCHIVE") | {name: .modules.module_author.name, title: .modules.module_dynamic.major.archive.title, bvid: .modules.module_dynamic.major.archive.bvid, mid: .modules.module_author.mid}]')

# 对比脚本两次运行之间是否有新视频投稿动态
CHANGE_VIDEO_DATA=$(jq --slurpfile old "$DYNAMIC_DATA" '($old[0] | map(.bvid)) as $old_bvids | [ .[] | select( .bvid as $bvid | $old_bvids | index($bvid) == null ) ]' <<< "$NEW_DYNAMIC_DATA")

if [ "$(jq -r 'length' <<< "$CHANGE_VIDEO_DATA")" -eq 0 ]; then
    MSG "[DEBUG]未检测到新视频，跳过下载。"
    echo "$NEW_DYNAMIC_DATA" > "$DYNAMIC_DATA"
    rm -f "$MSG_ID_FILE"
    exit 0
fi

# 过滤 UP 主 ID
FILTERED_DATA=$(jq --arg MODE "$DOWNLOAD_MODE" \
    --arg UP_IDS "$UP_ID" \
    -r '
    ($UP_IDS | split(",") | map(tonumber)) as $ID_LIST |
    if $MODE == "black" then
        [ .[] | select( .mid as $m | $ID_LIST | index($m) == null ) ]
    elif $MODE == "white" then
        [ .[] | select( .mid as $m | $ID_LIST | index($m) != null ) ]
    else
        .
    end' <<< "$CHANGE_VIDEO_DATA")

# 检查过滤后的数据是否为空，为空则跳过下载
if [ "$DOWNLOAD_MODE" = "black" ] && [ "$(jq -r 'length' <<< "$FILTERED_DATA")" -eq 0 ]; then
    MSG "[DEBUG]新投稿视频全部命中 UP 主下载黑名单，跳过下载。"
    echo "$NEW_DYNAMIC_DATA" > "$DYNAMIC_DATA"
    rm -f "$MSG_ID_FILE"
    exit 0
fi

if [ "$DOWNLOAD_MODE" = "white" ] && [ "$(jq -r 'length' <<< "$FILTERED_DATA")" -eq 0 ]; then
    MSG "[DEBUG]新投稿视频全部未命中 UP 主下载白名单，跳过下载。"
    echo "$NEW_DYNAMIC_DATA" > "$DYNAMIC_DATA"
    rm -f "$MSG_ID_FILE"
    exit 0
fi

# 下载视频
case "$DOWNLOAD_MODE" in
    "black"|"white")
        MSG "[DEBUG]当前下载模式：$([ "$DOWNLOAD_MODE" = "black" ] && echo "黑名单模式" || echo "白名单模式")。"
        MSG "[DEBUG]过滤名单中的 UP 主 ID：${UP_ID//,/, }。"

        while read -r DATA; do
            NAME=$(jq -r '.name' <<< "$DATA")
            TITLE=$(jq -r '.title' <<< "$DATA")
            BVID=$(jq -r '.bvid' <<< "$DATA")
            
            MSG "[INFO][EDIT_BEFORE]正在下载 ${NAME} 的新稿件「${TITLE}」(${BVID})..."
            
            cd "$ROOT_DOWNLOAD_DIR" || exit 1
            if [ "$ENABLE_BBDOWN_LOG" = "true" ]; then
                $BBDOWN "https://www.bilibili.com/video/$BVID"
            else
                $BBDOWN "https://www.bilibili.com/video/$BVID" >/dev/null 2>&1
            fi
            BBDOWN_EXIT_CODE=$?
            
            if [ $BBDOWN_EXIT_CODE -eq 0 ]; then
                MSG "[INFO][EDIT_AFTER]已下载 ${NAME} 的新稿件「${TITLE}」(${BVID})。"
            else
                MSG "[INFO][EDIT_AFTER]稿件下载失败。%0A调试信息:%0ADATA:${DATA}%0ACHANGE_VIDEO_DATA:%0A${CHANGE_VIDEO_DATA}%0ANEW_DYNAMIC_DATA:%0A${NEW_DYNAMIC_DATA}"
                FAILED_LOGS
            fi
        done <<< "$(jq -c '.[]' <<< "$FILTERED_DATA")"
        echo "$NEW_DYNAMIC_DATA" > "$DYNAMIC_DATA"
        ;;
        
    "all")
        while read -r DATA; do
            NAME=$(jq -r '.name' <<< "$DATA")
            TITLE=$(jq -r '.title' <<< "$DATA")
            BVID=$(jq -r '.bvid' <<< "$DATA")
            
            MSG "[INFO][EDIT_BEFORE]正在下载 ${NAME} 的新稿件「${TITLE}」(${BVID})..."
            
            cd "$ROOT_DOWNLOAD_DIR" || exit 1
            if [ "$ENABLE_BBDOWN_LOG" = "true" ]; then
                $BBDOWN "https://www.bilibili.com/video/$BVID"
            else
                $BBDOWN "https://www.bilibili.com/video/$BVID" >/dev/null 2>&1
            fi
            BBDOWN_EXIT_CODE=$?
            
            if [ $BBDOWN_EXIT_CODE -eq 0 ]; then
                MSG "[INFO][EDIT_AFTER]已下载 ${NAME} 的新稿件「${TITLE}」(${BVID})。"
            else
                MSG "[INFO][EDIT_AFTER]稿件下载失败。%0A调试信息:%0ADATA:${DATA}%0ACHANGE_VIDEO_DATA:%0A${CHANGE_VIDEO_DATA}%0ANEW_DYNAMIC_DATA:%0A${NEW_DYNAMIC_DATA}"
                FAILED_LOGS
            fi
        done <<< "$(jq -c '.[]' <<< "$CHANGE_VIDEO_DATA")"
        echo "$NEW_DYNAMIC_DATA" > "$DYNAMIC_DATA"
        ;;
esac

# 删除消息 ID 文件
rm -f "$MSG_ID_FILE"