# auto-bbdown

[![Docker Image](https://camo.githubusercontent.com/bea91f8507d40fd57169743db3179f5b5655b1ce1f34a74bd9ee38df2b35893c/68747470733a2f2f696d672e736869656c64732e696f2f646f636b65722f70756c6c732f73756c696e6767672f6175746f2d6262646f776e)](https://hub.docker.com/r/sulinggg/auto-bbdown) [![License](https://camo.githubusercontent.com/d8a997fc4ac09b15ac4680182262081fa654ca839436f8301061e6638322bd2d/68747470733a2f2f696d672e736869656c64732e696f2f6769746875622f6c6963656e73652f53754c696e6747472f6175746f2d6262646f776e)](https://github.com/SuLingGG/auto-bbdown/blob/main/LICENSE)

自动下载 B 站关注 UP 主最新投稿视频的解决方案，支持 Telegram 通知推送。采用 Docker 容器化设计，提供开箱即用的部署体验。

## 项目亮点

- **智能过滤**：提供 UP 主视频黑白名单机制

- **模块设计**：配置与脚本分离，便于维护升级
- **便捷部署**：Docker 容器化封装，支持扫码登录持久化
- **核心稳定**：集成 BBDown+Aria2 双引擎下载，支持断点续传
- **轻量高效**：基于 Shell 脚本配合 curl/jq 解析 B 站 API，无额外依赖
- **灵活扩展**：
  - 可配置日志输出级别
  - 集成 Telegram Bot 通知功能
  - 支持自定义下载器参数（兼容 yt-dlp/lux/yutto 等）
  - 脚本支持复用 BBDown Cookie，无需手动获取 Cookie

## 目录结构

### 项目本体

```
auto-bbdown/
├── config/
│   ├── auto-bbdown.config    # 主配置文件
│   └── BBDown.config         # BBDown配置文件
├── Dockerfile                # 容器构建文件
├── auto-bbdown.sh            # 核心逻辑脚本
└── entrypoint.sh             # 容器入口脚本
```

### 容器内部结构

```
/app/
├── bin/                      # 运行时文件
│   ├── BBDown               # 下载器主程序
│   └── BBDown.data          # 登录凭证文件
├── config/                   # 配置目录（挂载宿主机）
│   ├── auto-bbdown.config        # 本项目脚本配置目录
│   └── BBDown.config             # BBDown 程序配置文件
├── downloads/                # 视频下载目录（挂载宿主机）
├── logs/                     # 运行日志目录（挂载宿主机）
│   └── failed-logs/         # 下载失败记录
├── auto-bbdown.sh            # 核心逻辑脚本
└── entrypoint.sh             # 容器入口脚本
```

## 快速开始

### Docker 部署方案

#### 首次登录配置

```
docker run -it --rm \
    -v /path/to/bin:/app/bin \
    -v /path/to/config:/app/config \
    -v /path/to/downloads:/app/downloads \
    -v /path/to/logs:/app/logs \
    --name auto-bbdown \
    sulinggg/auto-bbdown:latest /app/bin/BBDown login
```

执行后终端会显示登录二维码（同时生成在 `/path/to/bin/qrcode.png`），使用 B 站 APP 扫码完成认证，完成认证后容器会自动销毁，凭证将持久化在 `/path/to/bin/BBDown.data` 文件中。

#### 常规运行

```
docker run -itd \
    -v /path/to/bin:/app/bin \
    -v /path/to/config:/app/config \
    -v /path/to/downloads:/app/downloads \
    -v /path/to/logs:/app/logs \
    --name auto-bbdown \
    sulinggg/auto-bbdown:latest
```

#### 日志查看

```
# 示例
tail -f /path/to/logs/bbdown_2025_01_01.log
```

### 原生运行方式

```
# 安装依赖
sudo apt update && sudo apt install -y curl jq ffmpeg aria2

# 部署BBDown
BBDOWN_URL="https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_linux-x64.zip"
mkdir -p ~/.local/bin
curl -L -o /tmp/BBDown.zip $BBDOWN_URL && unzip -j /tmp/BBDown.zip -d ~/.local/bin/ && chmod +x ~/.local/bin/BBDown

# 获取项目
git clone https://github.com/SuLingGG/auto-bbdown && cd auto-bbdown

# 初始化配置
~/.local/bin/BBDown login  # 扫码登录
vim config/auto-bbdown.config  # 按需配置

# 设置定时任务
(crontab -l ; echo "*/15 * * * /path/to/auto-bbdown.sh") | crontab -
```

## 镜像构建

```
git clone https://github.com/SuLingGG/auto-bbdown
cd auto-bbdown
docker build -t my-bbdown .
```

## 许可协议

本项目基于 [MIT License](https://github.com/SuLingGG/auto-bbdown/blob/main/LICENSE) 开源，欢迎二次开发与贡献代码。