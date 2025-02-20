# auto-bbdown

auto-bbdown.sh 个用于自动下载 B 站关注 UP 主最新投稿视频的脚本，支持通过 Telegram 发送下载状态通知。该项目使用 Docker 容器化，方便部署和使用。

## 项目结构

```
auto-bbdown
├── config
│   ├── auto-bbdown.config  # 本项目脚本配置目录
│   └── BBDown.config  # BBDown 程序配置文件
├── auto-bbdown.sh  # 核心脚本
├── Dockerfile  # 用于构建 Docker 镜像的 Dockerfile 文件
└── README.md  # 项目自述文件
```

## 文件说明

- **auto-bbdown.sh**: 主脚本，负责下载视频并处理相关逻辑。
- **config/auto-bbdown.config**: 主脚本的配置文件，定义了脚本运行间隔、日志设置、Telegram 消息设置等。
- **config/BBDown.config**: BBDown 的配置文件，包含下载时的参数设置。
- **downloads/**: 视频下载的根目录，容器外部挂载，用于存储下载的视频文件。
- **logs/**: 日志文件的根目录，容器外部挂载，用于存储运行日志。

## 构建 Docker 镜像

1. 确保已安装 Docker。
2. 在项目根目录下运行以下命令构建 Docker 镜像：

   ```
   docker build -t auto-bbdown .
   ```

## 运行 Docker 容器

运行 Docker 容器时，需要挂载配置、下载和日志目录：

```
docker run -d \
  -v /path/to/bin:/app/bin \
  -v /path/to/config:/app/config \
  -v /path/to/downloads:/app/downloads \
  -v /path/to/logs:/app/logs \
  --name auto-bbdown \
  sulinggg/auto-bbdown:latest
```

请将 `/path/to/bin、/path/to/config`、`/path/to/downloads` 和 `/path/to/logs` 替换为您本地的实际路径。

## 许可证

该项目遵循 MIT 许可证。