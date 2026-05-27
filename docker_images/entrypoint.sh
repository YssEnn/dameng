#!/bin/bash
# 任意命令失败时立即退出，避免数据库处于半初始化状态。
set -e

# 设置中文 UTF-8 环境，保证安装程序和数据库输出中文时不乱码。
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8

# 达梦软件安装目录。
DM_HOME=/home/dmdba/dmdbms

# 达梦实例配置文件路径，用于判断实例是否已经初始化。
DM_INI=/dmdata/data/DAMENG/dm.ini

# 首次启动容器时，如果安装目录不存在，则执行静默安装。
if [ ! -d "$DM_HOME/bin" ]; then
  echo ">>> 安装 DM8 软件"
  cd /dmiso

  # 确保安装程序具备执行权限。
  chmod +x DMInstall.bin

  # 通过交互输入完成命令行安装：
  # 1 选择中文，n 跳过 key 文件，21 选择典型安装，1 选择时区，
  # /home/dmdba/dmdbms 指定安装目录，y 确认安装。
  ./DMInstall.bin -i <<EOF
1
n
21
1
/home/dmdba/dmdbms
y
EOF
fi

# 如果实例配置文件不存在，说明数据目录尚未初始化。
if [ ! -f "$DM_INI" ]; then
  echo ">>> 初始化 DM8 实例"

  # 初始化数据库实例，固定数据库名、实例名、端口、字符集和默认管理员密码。
  "$DM_HOME/bin/dminit" \
    PATH=/dmdata/data \
    DB_NAME=DAMENG \
    INSTANCE_NAME=DMSERVER \
    PORT_NUM=5236 \
    CASE_SENSITIVE=0 \
    CHARSET=1 \
    SYSDBA_PWD=SYSDBA \
    SYSAUDITOR_PWD=SYSAUDITOR

  echo ">>> 设置 PostgreSQL 兼容模式"

  # 将 COMPATIBLE_MODE 设置为 7，使达梦启用 PostgreSQL 兼容模式。
  sed -i 's/^\s*COMPATIBLE_MODE\s*=.*/COMPATIBLE_MODE                 = 7/' "$DM_INI"
fi

# 打印当前兼容模式，便于启动日志中确认配置是否生效。
echo ">>> 当前兼容模式："
grep -i "COMPATIBLE_MODE" "$DM_INI" || true

# 使用 exec 让 dmserver 成为容器主进程，便于 Docker 正确转发信号。
echo ">>> 启动 DM8 数据库"
exec "$DM_HOME/bin/dmserver" "$DM_INI"
