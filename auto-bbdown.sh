#!/bin/bash

# 载入配置文件
source ./config/auto-bbdown.config

# 创建日志目录
mkdir -p "$LOG_DIR"
# 定义日志文件路径
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

    # 判断消息类型
    if [[ "$MESSAGE" == *"[INFO]"* ]]; then
        MSG_TYPE="INFO"
        MESSAGE=${MESSAGE//\[INFO\]/}
    elif [[ "$MESSAGE" == *"[DEBUG]"* ]]; then
        MSG_TYPE="DEBUG"
        MESSAGE=${MESSAGE//\[DEBUG\]/}
    fi

    # 判断编辑模式
    if [[ "$MESSAGE" == *"[EDIT_BEFORE]"* ]]; then
        EDIT_MODE="before"
        MESSAGE=${MESSAGE//\[EDIT_BEFORE\]/}
    elif [[ "$MESSAGE" == *"[EDIT_AFTER]"* ]]; then
        EDIT_MODE="after"
        MESSAGE=${MESSAGE//\[EDIT_AFTER\]/}
    fi

    local FULL_MSG="${TIMESTAMP} - ${MESSAGE}"
    local CLEAN_MSG=$(echo "$FULL_MSG" | sed -E 's/\[.*\]//g')

    # 输出消息到日志
    if { [ "$MSG_TYPE" = "INFO" ] || [ "$LOG_MSG_DEBUG" = "true" ]; }; then
        echo "$FULL_MSG"
    fi

    # 发送消息到 Telegram
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

# 记录失败日志函数
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

# 创建锁文件函数，防止多实例运行
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

# 检查是否存在动态数据文件
if [ ! -f "$DYNAMIC_DATA" ]; then
    # 解析新的动态数据
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
            
        "black"|"white")
            ;;
    esac
    
    echo "$NEW_DYNAMIC_DATA" > "$DYNAMIC_DATA"
    exit 0
fi

# 解析新的动态数据
NEW_DYNAMIC_DATA=$(echo "$DYNAMIC_RESPONSE" | jq '[.data.items[] | select(.modules.module_dynamic.major.type == "MAJOR_TYPE_ARCHIVE") | {name: .modules.module_author.name, title: .modules.module_dynamic.major.archive.title, bvid: .modules.module_dynamic.major.archive.bvid, mid: .modules.module_author.mid}]')

# 查找新的视频数据
CHANGE_VIDEO_DATA=$(jq --slurpfile old "$DYNAMIC_DATA" '($old[0] | map(.bvid)) as $old_bvids | [ .[] | select( .bvid as $bvid | $old_bvids | index($bvid) == null ) ]' <<< "$NEW_DYNAMIC_DATA")

# 如果没有检测到新视频，退出
rm -f "$MSG_ID_FILE"