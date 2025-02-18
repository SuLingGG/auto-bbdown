FROM debian:latest

# 安装必要的工具
RUN apt-get update && \
    apt-get install -y curl bash jq aria2 ffmpeg unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /app

# 复制脚本和配置文件
COPY auto-bbdown.sh ./bin/
COPY config/auto-bbdown.config ./config/
COPY config/BBDown.config ./config/

# 根据架构下载 BBDown 二进制文件
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        curl -L -o BBDown.zip https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_linux-x64.zip; \
    elif [ "$ARCH" = "aarch64" ]; then \
        curl -L -o BBDown.zip https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_linux-arm64.zip; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    unzip BBDown.zip -d ./bin && \
    rm BBDown.zip && \
    chmod +x ./bin/*

# 设置 cron 任务
RUN CRONTAB_JOB=$(cat /app/config/auto-bbdown.config | grep CRONTAB_TIME | cut -d '"' -f 2) && echo "$CRONTAB_JOB" >> /etc/crontab

# 创建挂载点
VOLUME ["/app/bin", "/app/config", "/app/downloads", "/app/logs"]

# 启动 cron
CMD ["cron", "-f"]