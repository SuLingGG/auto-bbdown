#!/bin/bash

# Step 1: 初始化目录（如果 /app/config 和 /app/bin 都为空）
if [ -z "$(ls -A /app/config)" ] && [ -z "$(ls -A /app/bin)" ]; then
    echo "Initializing config and bin files..."
    mv /app/tmp/config/* /app/config/
    mv /app/tmp/bin/* /app/bin/
    rm -rf /app/tmp
fi

# Step 2: 更新 cron 任务
CRONTAB_JOB=$(grep CRONTAB_TIME /app/config/auto-bbdown.config | cut -d '"' -f 2)
if [ -n "$CRONTAB_JOB" ]; then
    echo "Updating cron job..."
    sed -i '/auto-bbdown/d' /etc/crontab
    echo "$CRONTAB_JOB" >> /etc/crontab
fi

# Step 3: 执行用户命令或启动 cron
if [ $# -gt 0 ]; then
    # 如果用户提供了命令，直接执行（替代当前进程）
    exec "$@"
else
    # 默认行为：启动 cron 并保持前台运行
    echo "Starting cron..."
    exec cron -f
fi