FROM debian:latest

# 设置工作目录
WORKDIR /app

# 安装必要的工具
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates bash jq aria2 ffmpeg unzip cron && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /app/tmp/bin /app/config /app/downloads /app/logs

# 复制脚本和配置文件
COPY *.sh ./
COPY config/* ./tmp/config/

# 根据架构下载 BBDown 二进制文件并完成权限和时区设置
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        curl -L -o BBDown.zip https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_linux-x64.zip; \
    elif [ "$ARCH" = "aarch64" ]; then \
        curl -L -o BBDown.zip https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_linux-arm64.zip; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    unzip BBDown.zip -d /app/tmp/bin && \
    rm BBDown.zip && \
    chmod +x /app/tmp/bin/BBDown && \
    chmod +x /app/*.sh && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 创建挂载点
VOLUME ["/app/bin", "/app/config", "/app/downloads", "/app/logs"]

# 设置入口点
ENTRYPOINT ["/app/entrypoint.sh"]