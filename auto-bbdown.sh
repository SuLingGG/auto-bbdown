#!/bin/bash

# 载入配置文件 (建议配置为绝对路径)
source /app/config/auto-bbdown.config

mkdir -p "$LOG_DIR"
mkdir -p "$LOG_DIR"/"failed-logs"
mkdir -p "$ROOT_DOWNLOAD_DIR"

LOG_FILE="$LOG_DIR/bbdown_$(date +%Y-%m-%d).log"
JOB_LOG_FILE="$LOG_DIR/bbdown_job_$(date +"%Y-%m-%d %H-%M-%S.%3N").log"

exec > >(tee -a "$LOG_FILE" | tee -a "$JOB_LOG_FILE" | grep -avE 'version|查阅|nilaoda|^[[:space:]]*$') 2>&1

GET_TIMESTAMP() {
    echo "$(date +"[%Y-%m-%d %H:%M:%S.%3N]")"
}

LOG() {
    local LOG_MESSAGE="$1"
    local LOG_TYPE="DEBUG"
    local TIMESTAMP=$(GET_TIMESTAMP)

    if [[ "$LOG_MESSAGE" == *"[INFO]"* ]]; then
        LOG_TYPE="INFO"
        LOG_MESSAGE=${LOG_MESSAGE//\[INFO\]/}
    elif [[ "$LOG_MESSAGE" == *"[DEBUG]"* ]]; then
        LOG_TYPE="DEBUG"
        LOG_MESSAGE=${LOG_MESSAGE//\[DEBUG\]/}
    fi

    local FULL_LOG="${TIMESTAMP} - ${LOG_MESSAGE}"

    if [ "$LOG_DEBUG" = "false" ]; then
        if [ "$LOG_TYPE" = "INFO" ]; then
            echo "$FULL_LOG"
        fi
    else
        echo "$FULL_LOG"
    fi
}

FAILED_LOG () {
    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        mv "$JOB_LOG_FILE" "$LOG_DIR/failed-logs/"
    fi
}
trap FAILED_LOG EXIT

MSG() {
    local MESSAGE="$1"
    local MSG_TYPE="DEBUG"
    local EDIT_MODE="new"
    local TIMESTAMP=$(GET_TIMESTAMP)

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
    local CLEAN_MSG=$(echo "$FULL_MSG" | sed -E 's/\[INFO\]|\[DEBUG\]|\[EDIT_BEFORE\]|\[EDIT_AFTER\]//g')

    if [ "$MSG_TYPE" = "DEBUG" ] || [ "$LOG_DEBUG" = "true" ]; then
        echo "$FULL_MSG"
        echo "$FULL_MSG" >> "$LOG_FILE"
    fi

    if [ "$ENABLE_TG_MSG" = "true" ]; then
        if [ "$MSG_TYPE" = "INFO" ] || { [ "$MSG_TYPE" = "DEBUG" ] && [ "$TG_MSG_DEBUG" = "true" ]; }; then
            case $EDIT_MODE in
            "before")
                local RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                    -d chat_id="${CHAT_ID}" \
                    -d text="${CLEAN_MSG}")
                local MSG_ID=$(echo "$RESPONSE" | jq -r '.result.message_id')
                [ -n "$MSG_ID" ] && echo "$MSG_ID" >"$MSG_ID_FILE"
                ;;
            "after")
                if [ -f "$MSG_ID_FILE" ]; then
                    local MSG_ID=$(cat "$MSG_ID_FILE")
                    curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/editMessageText" \
                        -d chat_id="${CHAT_ID}" \
                        -d message_id="${MSG_ID}" \
                        -d text="${CLEAN_MSG}" >/dev/null
                    rm -f "$MSG_ID_FILE"
                fi
                ;;
            *)
                curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
                    -d chat_id="${CHAT_ID}" \
                    -d text="${CLEAN_MSG}" >/dev/null
                ;;
            esac
        fi
    fi
}

CREATE_LOCK() {
    if [ -f "$LOCK_FILE" ]; then
        LOG "[INFO]另一个实例正在运行，退出..."
        exit 1
    fi
    touch "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; exit' SIGINT SIGTERM EXIT
}

CREATE_LOCK

LOG "[DEBUG]开始获取动态响应..."
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
if [ $? -ne 0 ]; then
    LOG "[INFO]获取动态响应失败"
    exit 1
fi
LOG "[DEBUG]获取动态响应成功"

if [ ! -f "$DYNAMIC_DATA" ]; then
    LOG "[DEBUG]从动态响应提取最新动态信息..."
    NEW_DYNAMIC_DATA=$(echo "$DYNAMIC_RESPONSE" | jq '[.data.items[] | select(.modules.module_dynamic.major.type == "MAJOR_TYPE_ARCHIVE") | {name: .modules.module_author.name, title: .modules.module_dynamic.major.archive.title, bvid: .modules.module_dynamic.major.archive.bvid, mid: .modules.module_author.mid}]')
    if [ $? -ne 0 ]; then
        LOG "[INFO]提取最新动态信息失败"
        exit 1
    fi
    LOG "[DEBUG]提取最新动态信息成功"

    case "$DOWNLOAD_MODE" in
    "all")
        NAME=$(echo "$NEW_DYNAMIC_DATA" | jq -r '.[0].name')
        TITLE=$(echo "$NEW_DYNAMIC_DATA" | jq -r '.[0].title')
        BVID=$(echo "$NEW_DYNAMIC_DATA" | jq -r '.[0].bvid')

        LOG "[DEBUG]输出调试信息 NAME: $NAME"
        LOG "[DEBUG]输出调试信息 TITLE: $TITLE"
        LOG "[DEBUG]输出调试信息 BVID: $BVID"

        MSG "[INFO][EDIT_BEFORE]首次运行，正在下载 ${NAME} 的稿件「${TITLE}」(${BVID})..."

        cd "$ROOT_DOWNLOAD_DIR" || exit 1
        if [ "$ENABLE_BBDOWN_LOG" = "true" ]; then
            $BBDOWN "https://www.bilibili.com/video/$BVID"
        else
            $BBDOWN "https://www.bilibili.com/video/$BVID" >/dev/null 2>&1
        fi
        BBDOWN_EXIT_CODE=$?

        if [ $BBDOWN_EXIT_CODE -eq 0 ]; then
            MSG "[INFO][EDIT_AFTER]首次运行，已下载 ${NAME} 的稿件「${TITLE}」(${BVID})"
        else
            MSG "[INFO][EDIT_AFTER]稿件下载失败"
        fi
        ;;

    "black" | "white")
        MODE_NAME=$([ "$DOWNLOAD_MODE" = "black" ] && echo "黑名单" || echo "白名单")
        MSG "[INFO]检测到脚本第一次运行，由于已定义下载${MODE_NAME}，脚本将在后续运行过程中检测并下载新增视频"
        ;;
    esac
    LOG "[DEBUG]首次下载结束"
    echo "$NEW_DYNAMIC_DATA" >"$DYNAMIC_DATA"
    exit 0
fi

LOG "[DEBUG]从动态响应提取最新动态信息..."
NEW_DYNAMIC_DATA=$(echo "$DYNAMIC_RESPONSE" | jq '[.data.items[] | select(.modules.module_dynamic.major.type == "MAJOR_TYPE_ARCHIVE") | {name: .modules.module_author.name, title: .modules.module_dynamic.major.archive.title, bvid: .modules.module_dynamic.major.archive.bvid, mid: .modules.module_author.mid}]')
if [ $? -ne 0 ]; then
    LOG "[INFO]从动态响应提取最新动态信息失败"
    exit 1
fi
LOG "[DEBUG]从动态响应提取最新动态信息成功"

LOG "[DEBUG]对比历史数据提取动态变动信息..."
CHANGE_VIDEO_DATA=$(jq --slurpfile old "$DYNAMIC_DATA" '($old[0] | map(.bvid)) as $old_bvids | [ .[] | select( .bvid as $bvid | $old_bvids | index($bvid) == null ) ]' <<<"$NEW_DYNAMIC_DATA")
if [ $? -ne 0 ]; then
    LOG "[INFO]对比历史数据提取动态变动信息失败"
    exit 1
fi
LOG "[DEBUG]对比历史数据提取动态变动信息成功"

if [ "$(jq -r 'length' <<<"$CHANGE_VIDEO_DATA")" -eq 0 ]; then
    MSG "[DEBUG]未检测到新视频，跳过下载"
    echo "$NEW_DYNAMIC_DATA" >"$DYNAMIC_DATA"
    rm -f "$MSG_ID_FILE"
    exit 0
fi

LOG "[DEBUG]从 UP 主下载黑/白名单中过滤动态信息..."
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
    end' <<<"$CHANGE_VIDEO_DATA")
if [ $? -ne 0 ]; then
    LOG "[INFO]黑/白名单过滤失败"
    exit 1
fi
LOG "[DEBUG]黑/白名单过滤成功"

case "$DOWNLOAD_MODE" in
"black" | "white")
    LOG "[DEBUG]当前下载模式: $([ "$DOWNLOAD_MODE" = "black" ] && echo "黑名单模式" || echo "白名单模式")"
    LOG "[DEBUG]过滤名单中的 UP 主 ID: ${UP_ID//,/, }"

    if [ "$DOWNLOAD_MODE" = "black" ] && [ "$(jq -r 'length' <<<"$FILTERED_DATA")" -eq 0 ]; then
        MSG "[DEBUG]新投稿视频全部命中 UP 主下载黑名单，跳过下载"
        echo "$NEW_DYNAMIC_DATA" >"$DYNAMIC_DATA"
        rm -f "$MSG_ID_FILE"
        exit 0
    fi

    if [ "$DOWNLOAD_MODE" = "white" ] && [ "$(jq -r 'length' <<<"$FILTERED_DATA")" -eq 0 ]; then
        MSG "[DEBUG]新投稿视频全部未命中 UP 主下载白名单，跳过下载"
        echo "$NEW_DYNAMIC_DATA" >"$DYNAMIC_DATA"
        rm -f "$MSG_ID_FILE"
        exit 0
    fi

    echo -e "$(date +"[%Y-%m-%d %H:%M:%S.%3N]") - 输出调试信息 FILTERED_DATA: \n${FILTERED_DATA}"
    mapfile -t LINES < <(jq -c '.[]' <<<"$FILTERED_DATA")
    for VIDEO_DATA in "${LINES[@]}"; do
        NAME=$(jq -r '.name' <<<"$VIDEO_DATA")
        TITLE=$(jq -r '.title' <<<"$VIDEO_DATA")
        BVID=$(jq -r '.bvid' <<<"$VIDEO_DATA")

        LOG "[DEBUG]输出调试信息 VIDEO_DATA: $VIDEO_DATA"
        LOG "[DEBUG]输出调试信息 NAME: $NAME"
        LOG "[DEBUG]输出调试信息 TITLE: $TITLE"
        LOG "[DEBUG]输出调试信息 BVID: $BVID"

        MSG "[INFO][EDIT_BEFORE]正在下载 ${NAME} 的新稿件「${TITLE}」(${BVID})..."

        cd "$ROOT_DOWNLOAD_DIR" || exit 1
        if [ "$ENABLE_BBDOWN_LOG" = "true" ]; then
            $BBDOWN "https://www.bilibili.com/video/$BVID"
        else
            $BBDOWN "https://www.bilibili.com/video/$BVID" >/dev/null 2>&1
        fi
        BBDOWN_EXIT_CODE=$?

        if [ $BBDOWN_EXIT_CODE -eq 0 ]; then
            MSG "[INFO][EDIT_AFTER]已下载 ${NAME} 的新稿件「${TITLE}」(${BVID})"
        else
            MSG "[INFO][EDIT_AFTER]稿件下载失败"
        fi
    done <<<"$(jq -c '.[]' <<<"$FILTERED_DATA")"
    LOG "[DEBUG]本次下载流程结束"
    echo "$NEW_DYNAMIC_DATA" >"$DYNAMIC_DATA"
    ;;

"all")
    :
    LOG "[DEBUG]输出调试信息 CHANGE_VIDEO_DATA: \n${CHANGE_VIDEO_DATA}"
    mapfile -t LINES < <(jq -c '.[]' <<<"$CHANGE_VIDEO_DATA")
    for VIDEO_DATA in "${LINES[@]}"; do
        NAME=$(jq -r '.name' <<<"$VIDEO_DATA")
        TITLE=$(jq -r '.title' <<<"$VIDEO_DATA")
        BVID=$(jq -r '.bvid' <<<"$VIDEO_DATA")

        LOG "[DEBUG]输出调试信息 VIDEO_DATA: $VIDEO_DATA"
        LOG "[DEBUG]输出调试信息 NAME: $NAME"
        LOG "[DEBUG]输出调试信息 TITLE: $TITLE"
        LOG "[DEBUG]输出调试信息 BVID: $BVID"

        MSG "[INFO][EDIT_BEFORE]正在下载 ${NAME} 的新稿件「${TITLE}」(${BVID})"

        cd "$ROOT_DOWNLOAD_DIR" || exit 1
        if [ "$ENABLE_BBDOWN_LOG" = "true" ]; then
            $BBDOWN "https://www.bilibili.com/video/$BVID"
        else
            $BBDOWN "https://www.bilibili.com/video/$BVID" >/dev/null 2>&1
        fi
        BBDOWN_EXIT_CODE=$?

        if [ $BBDOWN_EXIT_CODE -eq 0 ]; then
            MSG "[INFO][EDIT_AFTER]已下载 ${NAME} 的新稿件「${TITLE}」(${BVID})"
        else
            MSG "[INFO][EDIT_AFTER]稿件下载失败"
        fi
    done
    LOG "[DEBUG]本次下载流程结束"
    echo "$NEW_DYNAMIC_DATA" >"$DYNAMIC_DATA"
    ;;
esac
rm -f "$MSG_ID_FILE" "$JOB_LOG_FILE"
