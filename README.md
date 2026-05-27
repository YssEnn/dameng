# dameng

本仓库用于维护达梦数据库 DM8 的 Docker 镜像构建文件和容器启动脚本。

## 目录结构

```text
.
├── README.md
└── docker_images
    ├── Dockerfile
    ├── entrypoint.sh
    └── README.md
```

## 内容说明

- `docker_images/Dockerfile`：基于 `centos:7` 构建达梦 DM8 运行镜像，安装系统依赖、配置中文 UTF-8 环境、创建达梦运行用户、limits 和数据目录。
- `docker_images/entrypoint.sh`：容器入口脚本，负责首次启动时安装 DM8、初始化数据库实例、设置 PostgreSQL 兼容模式，并以前台 `dmserver` 启动数据库。
- `docker_images/README.md`：Docker 镜像构建和容器运行说明。

## 快速开始

进入镜像目录：

```bash
cd docker_images
```

将达梦安装包放到该目录，zip 内需要包含 `.iso` 安装介质，文件名需要与 `Dockerfile` 中的 `COPY` 指令保持一致：

```text
dm8_20260427_x86_CentOS7_64.zip
```

构建镜像：

```bash
docker build -t dameng:dm8_20260427_x86_CentOS7 .
```

启动容器：

```bash
docker run -d \
  --name dameng-dm8 \
  -p 5236:5236 \
  --ulimit nofile=65536:65536 \
  --ulimit nproc=65536:65536 \
  -e DM_SYSDBA_PWD='DMdba_123' \
  -e DM_SYSAUDITOR_PWD='DMauditor_123' \
  -v dameng-data:/dmdata \
  dameng:dm8_20260427_x86_CentOS7
```

更多配置和注意事项见 [docker_images/README.md](docker_images/README.md)。
