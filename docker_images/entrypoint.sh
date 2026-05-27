#!/bin/bash
# 任意命令失败时立即退出，避免数据库处于半初始化状态。
set -euo pipefail

# 设置中文 UTF-8 环境，保证安装程序和数据库输出中文时不乱码。
export LANG=${LANG:-zh_CN.UTF-8}
export LC_ALL=${LC_ALL:-zh_CN.UTF-8}

# 达梦软件和数据目录。数据目录通常挂载为 Docker volume。
DM_HOME=${DM_HOME:-/home/dmdba/dmdbms}
DM_DATA_DIR=${DM_DATA_DIR:-/dmdata/data}
DM_ARCH_DIR=${DM_ARCH_DIR:-/dmdata/arch}
DM_BAK_DIR=${DM_BAK_DIR:-/dmdata/dmbak}
DM_DB_NAME=${DM_DB_NAME:-DAMENG}
DM_INSTANCE_NAME=${DM_INSTANCE_NAME:-DMSERVER}
DM_PORT_NUM=${DM_PORT_NUM:-5236}
DM_CASE_SENSITIVE=${DM_CASE_SENSITIVE:-0}
DM_CHARSET=${DM_CHARSET:-1}
DM_COMPATIBLE_MODE=${DM_COMPATIBLE_MODE:-7}
DM_SYSDBA_PWD=${DM_SYSDBA_PWD:-DMdba_123}
DM_SYSAUDITOR_PWD=${DM_SYSAUDITOR_PWD:-DMauditor_123}
DM_NOFILE_LIMIT=${DM_NOFILE_LIMIT:-65536}
DM_NPROC_LIMIT=${DM_NPROC_LIMIT:-65536}
DM_FIX_OWNERSHIP=${DM_FIX_OWNERSHIP:-1}
DM_RUN_ROOT_INSTALLER=${DM_RUN_ROOT_INSTALLER:-1}
DM_REGISTER_SERVICE=${DM_REGISTER_SERVICE:-0}
DM_SERVICE_SUFFIX=${DM_SERVICE_SUFFIX:-$DM_INSTANCE_NAME}
DM_INI=${DM_INI:-$DM_DATA_DIR/$DM_DB_NAME/dm.ini}

export DM_HOME
export PATH=$DM_HOME/bin:$PATH

run_as_dmdba() {
  if [ "$(id -u)" -eq 0 ]; then
    runuser -u dmdba -- "$@"
  else
    "$@"
  fi
}

exec_as_dmdba() {
  if [ "$(id -u)" -ne 0 ]; then
    exec "$@"
  fi

  if command -v setpriv >/dev/null 2>&1; then
    local dmdba_uid dinstall_gid
    dmdba_uid=$(id -u dmdba)
    dinstall_gid=$(getent group dinstall | cut -d: -f3)
    exec setpriv --reuid="$dmdba_uid" --regid="$dinstall_gid" --init-groups "$@"
  fi

  exec runuser -u dmdba -- "$@"
}

set_runtime_limits() {
  if ! ulimit -n "$DM_NOFILE_LIMIT" 2>/dev/null; then
    echo ">>> 警告：无法将 nofile 设置为 $DM_NOFILE_LIMIT，请检查 Docker --ulimit 配置"
  fi

  if ! ulimit -u "$DM_NPROC_LIMIT" 2>/dev/null; then
    echo ">>> 警告：无法将 nproc 设置为 $DM_NPROC_LIMIT，请检查 Docker --ulimit 配置"
  fi
}

prepare_directories() {
  mkdir -p "$DM_DATA_DIR" "$DM_ARCH_DIR" "$DM_BAK_DIR"

  if [ "$(id -u)" -ne 0 ]; then
    return
  fi

  local dir owner
  for dir in "$DM_DATA_DIR" "$DM_ARCH_DIR" "$DM_BAK_DIR"; do
    if [ "$DM_FIX_OWNERSHIP" = "1" ]; then
      owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || true)
      if [ "$owner" != "dmdba:dinstall" ]; then
        chown -R dmdba:dinstall "$dir"
      fi
    fi
    chmod 755 "$dir"
  done

  [ -d /dmiso ] && chown -R dmdba:dinstall /dmiso
  [ -d "$DM_HOME" ] && chown -R dmdba:dinstall "$DM_HOME"
}

find_dm_installer() {
  if [ -n "${DM_INSTALLER:-}" ] && [ -f "$DM_INSTALLER" ]; then
    printf '%s\n' "$DM_INSTALLER"
    return
  fi

  if [ -f /dmiso/DMInstall.bin ]; then
    printf '%s\n' /dmiso/DMInstall.bin
    return
  fi

  find /dmiso -maxdepth 3 -type f -name DMInstall.bin -print -quit
}

install_dm() {
  if [ -x "$DM_HOME/bin/dminit" ] && [ -x "$DM_HOME/bin/dmserver" ]; then
    return
  fi

  echo ">>> 安装 DM8 软件"

  local installer installer_dir installer_name
  installer=$(find_dm_installer)
  if [ -z "$installer" ]; then
    echo ">>> 错误：未找到 DMInstall.bin，请确认安装包已正确解压到 /dmiso"
    exit 1
  fi

  chmod +x "$installer"
  installer_dir=$(dirname "$installer")
  installer_name=$(basename "$installer")

  (
    cd "$installer_dir"
    # 官方交互安装顺序：中文、不输入 key、选择中国时区、典型安装、安装目录、确认。
    printf '1\nn\n21\n1\n%s\ny\n' "$DM_HOME" | run_as_dmdba "./$installer_name" -i
  )
}

run_root_installer() {
  if [ "$DM_RUN_ROOT_INSTALLER" != "1" ]; then
    return
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo ">>> 警告：当前非 root，跳过 root_installer.sh"
    return
  fi

  local script marker
  script="$DM_HOME/script/root/root_installer.sh"
  marker="$DM_HOME/.root_installer.done"

  if [ -x "$script" ] && [ ! -f "$marker" ]; then
    echo ">>> 执行达梦 root 配置脚本"
    "$script"
    touch "$marker"
    chown dmdba:dinstall "$marker"
  fi
}

set_compatible_mode() {
  if [ -z "$DM_COMPATIBLE_MODE" ]; then
    return
  fi

  if grep -qi '^[[:space:]]*COMPATIBLE_MODE[[:space:]]*=' "$DM_INI"; then
    sed -i -E "s/^[[:space:]]*COMPATIBLE_MODE[[:space:]]*=.*/COMPATIBLE_MODE                 = $DM_COMPATIBLE_MODE/" "$DM_INI"
  else
    printf '\nCOMPATIBLE_MODE                 = %s\n' "$DM_COMPATIBLE_MODE" >> "$DM_INI"
  fi
}

init_dm_instance() {
  if [ -f "$DM_INI" ]; then
    return
  fi

  echo ">>> 初始化 DM8 实例"

  if [ "$DM_SYSDBA_PWD" = "DMdba_123" ] || [ "$DM_SYSAUDITOR_PWD" = "DMauditor_123" ]; then
    echo ">>> 警告：正在使用默认初始化密码，生产环境请通过 DM_SYSDBA_PWD 和 DM_SYSAUDITOR_PWD 覆盖"
  fi

  local init_args=(
    "PATH=$DM_DATA_DIR"
    "DB_NAME=$DM_DB_NAME"
    "INSTANCE_NAME=$DM_INSTANCE_NAME"
    "PORT_NUM=$DM_PORT_NUM"
    "CASE_SENSITIVE=$DM_CASE_SENSITIVE"
    "CHARSET=$DM_CHARSET"
    "SYSDBA_PWD=$DM_SYSDBA_PWD"
    "SYSAUDITOR_PWD=$DM_SYSAUDITOR_PWD"
  )

  [ -n "${DM_PAGE_SIZE:-}" ] && init_args+=("PAGE_SIZE=$DM_PAGE_SIZE")
  [ -n "${DM_EXTENT_SIZE:-}" ] && init_args+=("EXTENT_SIZE=$DM_EXTENT_SIZE")
  [ -n "${DM_LOG_SIZE:-}" ] && init_args+=("LOG_SIZE=$DM_LOG_SIZE")

  run_as_dmdba "$DM_HOME/bin/dminit" "${init_args[@]}"
  set_compatible_mode
}

register_dm_service() {
  if [ "$DM_REGISTER_SERVICE" != "1" ]; then
    return
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo ">>> 警告：当前非 root，跳过数据库服务注册"
    return
  fi

  local script service_file
  script="$DM_HOME/script/root/dm_service_installer.sh"
  service_file="$DM_HOME/bin/DmService$DM_SERVICE_SUFFIX"

  if [ ! -x "$script" ]; then
    echo ">>> 警告：未找到 dm_service_installer.sh，跳过数据库服务注册"
    return
  fi

  if [ -x "$service_file" ]; then
    return
  fi

  echo ">>> 注册达梦数据库服务 DmService$DM_SERVICE_SUFFIX"
  "$script" -t dmserver -dm_ini "$DM_INI" -p "$DM_SERVICE_SUFFIX"
}

set_runtime_limits
prepare_directories
install_dm
run_root_installer
init_dm_instance
register_dm_service

echo ">>> 当前兼容模式："
grep -i 'COMPATIBLE_MODE' "$DM_INI" || true

# Docker 容器中使用前台 dmserver，便于 Docker 正确转发停止信号。
echo ">>> 启动 DM8 数据库"
exec_as_dmdba "$DM_HOME/bin/dmserver" "$DM_INI"
