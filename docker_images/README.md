# 达梦 DM8 Docker 镜像

该目录用于构建和运行达梦数据库 DM8 容器镜像。

## 文件说明

- `Dockerfile`：定义镜像构建流程，包括基础镜像、语言环境、系统依赖、达梦用户、数据目录和入口脚本。
- `entrypoint.sh`：容器启动入口，负责首次安装 DM8、初始化实例、设置兼容模式并启动 `dmserver`。
- `dm8_20260427_x86_CentOS7_64.zip`：达梦 DM8 安装包，zip 内需要包含 `.iso` 安装介质，构建镜像前手动放入当前目录。

## 构建前准备

确认当前目录下存在安装包：

```bash
ls dm8_20260427_x86_CentOS7_64.zip
```

如果安装包名称不同，需要同步修改 `Dockerfile` 中的 `COPY` 指令。

## 构建镜像

在 `docker_images` 目录下执行：

```bash
docker build -t dameng-dm8:20260427_x86_CentOS7 .
```

构建过程会完成以下操作：

- 使用 `centos:7` 作为基础镜像。
- 切换 CentOS 7 软件源到清华 CentOS Vault。
- 安装 `unzip`、`glibc-common`、`libaio`、`net-tools`、`util-linux` 等依赖。
- 创建 `dmdba` 用户和 `dinstall` 用户组，并写入达梦运行所需 limits 配置。
- 创建 `/dmdata/data`、`/dmdata/arch`、`/dmdata/dmbak` 等数据目录。
- 解压 zip 到临时目录，loop 挂载其中的 ISO，并将 ISO 内的安装文件复制到 `/dmiso`。

构建阶段需要 Docker 环境允许 `mount -o loop`。如果构建报 `Operation not permitted`，需要在支持 loop mount 的构建环境中执行，或改为提前在宿主机解出 ISO 内容后再构建。

## 启动容器

推荐使用 Docker volume 持久化数据库数据：

```bash
docker run -d \
  --name dameng-dm8 \
  -p 5236:5236 \
  --ulimit nofile=65536:65536 \
  --ulimit nproc=65536:65536 \
  -e DM_SYSDBA_PWD='DMdba_123' \
  -e DM_SYSAUDITOR_PWD='DMauditor_123' \
  -v dameng-data:/dmdata \
  dameng-dm8:20260427_x86_CentOS7
```
window
```bash
docker run -d --name dameng-dm8 -p 5236:5236 --ulimit nofile=65536:65536 --ulimit nproc=65536:65536 -e DM_SYSDBA_PWD='DMdba_123' -e DM_SYSAUDITOR_PWD='DMauditor_123' -v D:\DevFile\DockerData\dmdata:/dmdata dameng-dm8:20260427_x86_CentOS7
```

查看启动日志：

```bash
docker logs -f dameng-dm8
```

停止容器：

```bash
docker stop dameng-dm8
```

删除容器：

```bash
docker rm dameng-dm8
```

## 初始化参数

这些参数只在首次创建实例时生效；复用已有 `/dmdata` 数据卷时，脚本会按现有 `dm.ini` 启动，不会重新初始化实例。

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DM_HOME` | `/home/dmdba/dmdbms` | 达梦软件安装目录 |
| `DM_DATA_DIR` | `/dmdata/data` | 实例数据根目录 |
| `DM_ARCH_DIR` | `/dmdata/arch` | 归档目录 |
| `DM_BAK_DIR` | `/dmdata/dmbak` | 备份目录 |
| `DM_DB_NAME` | `DAMENG` | 数据库名 |
| `DM_INSTANCE_NAME` | `DMSERVER` | 实例名 |
| `DM_PORT_NUM` | `5236` | 数据库监听端口 |
| `DM_CASE_SENSITIVE` | `0` | 是否大小写敏感 |
| `DM_CHARSET` | `1` | 字符集，默认 UTF-8 |
| `DM_COMPATIBLE_MODE` | `7` | PostgreSQL 兼容模式；设为空可跳过写入 |
| `DM_SYSDBA_PWD` | `DMdba_123` | `SYSDBA` 初始化密码 |
| `DM_SYSAUDITOR_PWD` | `DMauditor_123` | `SYSAUDITOR` 初始化密码 |
| `DM_PAGE_SIZE` | 空 | 可选，传给 `dminit` |
| `DM_EXTENT_SIZE` | 空 | 可选，传给 `dminit` |
| `DM_LOG_SIZE` | 空 | 可选，传给 `dminit` |

## 服务注册

Docker 默认用前台 `dmserver` 作为主进程启动数据库，这样可以让 Docker 正确转发停止信号。需要按官方方式生成 `DmService*` 服务脚本时，可以在首次启动或已有实例启动时增加：

```bash
-e DM_REGISTER_SERVICE=1
```

脚本会执行：

```bash
$DM_HOME/script/root/dm_service_installer.sh -t dmserver -dm_ini "$DM_INI" -p "$DM_SERVICE_SUFFIX"
```

容器内不使用该服务脚本启动数据库；服务脚本主要用于需要进入容器内按官方命令手工管理服务的场景。

## 启动逻辑

容器启动时会执行 `entrypoint.sh`：

1. 以 root 设置运行时 limits，创建并修复 `/dmdata` 目录权限。
2. 如果 `/home/dmdba/dmdbms/bin/dmserver` 不存在，则切换到 `dmdba` 执行 DM8 安装。
3. 安装完成后以 root 执行达梦 `root_installer.sh`。
4. 如果 `$DM_INI` 不存在，则切换到 `dmdba` 执行 `dminit` 初始化实例。
5. 初始化完成后按 `DM_COMPATIBLE_MODE` 写入兼容模式。
6. 如启用 `DM_REGISTER_SERVICE=1`，执行服务注册。
7. 使用 `dmdba` 前台启动 `dmserver`。

## 连接信息

宿主机连接地址：

```text
127.0.0.1:5236
```

容器网络内连接地址：

```text
dameng-dm8:5236
```

## 注意事项

- 首次启动会执行安装和初始化，耗时会比普通启动更长。
- `/dmdata` 建议始终挂载到 Docker volume 或宿主机目录，否则删除容器后数据库数据会丢失。
- 当前脚本内置的默认管理员密码仅适合开发或测试环境；生产环境必须通过环境变量覆盖。
- 重新使用已有 `/dmdata` 数据卷时，脚本会跳过实例初始化，直接按现有 `dm.ini` 启动数据库。
- `DM_DB_NAME`、`DM_CASE_SENSITIVE`、`DM_CHARSET`、`DM_PAGE_SIZE` 等初始化参数创建实例后不能靠重启容器修改；需要修改时应重新初始化新的数据卷。
