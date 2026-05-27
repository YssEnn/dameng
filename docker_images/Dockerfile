# 使用 CentOS 7 作为达梦数据库运行环境的基础镜像。
FROM centos:7

# 设置容器默认中文 UTF-8 语言环境，避免安装和运行时中文乱码。
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# 定义达梦数据库安装目录，并将数据库命令加入 PATH。
ENV DM_HOME=/home/dmdba/dmdbms
ENV DM_DATA_DIR=/dmdata/data
ENV DM_ARCH_DIR=/dmdata/arch
ENV DM_BAK_DIR=/dmdata/dmbak
ENV PATH=$DM_HOME/bin:$PATH

# 拷贝达梦外层 zip 安装包和容器入口脚本到镜像中。
COPY dm8_20260427_x86_CentOS7_64.zip /tmp/dm8.zip
COPY entrypoint.sh /entrypoint.sh

# CentOS 7 已停止常规维护，这里切换到清华 CentOS Vault 镜像源。
RUN rm -f /etc/yum.repos.d/*.repo && \
    cat > /etc/yum.repos.d/CentOS-Base.repo <<'EOF'
# 基础软件仓库。
[base]
name=CentOS-7 - Base
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-vault/7.9.2009/os/$basearch/
gpgcheck=0
enabled=1

# 系统更新仓库。
[updates]
name=CentOS-7 - Updates
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-vault/7.9.2009/updates/$basearch/
gpgcheck=0
enabled=1

# 额外软件仓库。
[extras]
name=CentOS-7 - Extras
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos-vault/7.9.2009/extras/$basearch/
gpgcheck=0
enabled=1
EOF

# 安装运行依赖、创建达梦运行用户和数据目录，并从 zip 内的 ISO 提取安装介质。
RUN set -eux && \
    yum clean all && \
    yum install -y unzip bsdtar glibc-common libaio net-tools util-linux && \
    localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8 && \
    groupadd -g 2001 dinstall && \
    useradd -g dinstall -m -d /home/dmdba -s /bin/bash -u 2001 dmdba && \
    printf '%s\n' \
      'dmdba soft nice 0' \
      'dmdba hard nice 0' \
      'dmdba soft as unlimited' \
      'dmdba hard as unlimited' \
      'dmdba soft fsize unlimited' \
      'dmdba hard fsize unlimited' \
      'dmdba soft nproc 65536' \
      'dmdba hard nproc 65536' \
      'dmdba soft nofile 65536' \
      'dmdba hard nofile 65536' \
      'dmdba soft core unlimited' \
      'dmdba hard core unlimited' \
      'dmdba soft data unlimited' \
      'dmdba hard data unlimited' >> /etc/security/limits.conf && \
    mkdir -p /dmiso /tmp/dm8_extract "$DM_DATA_DIR" "$DM_ARCH_DIR" "$DM_BAK_DIR" && \
    unzip /tmp/dm8.zip -d /tmp/dm8_extract && \
    iso_path="$(find /tmp/dm8_extract -maxdepth 3 -type f -name '*.iso' -print -quit)" && \
    if [ -z "$iso_path" ]; then echo "未在 dm8 zip 安装包中找到 ISO 文件"; exit 1; fi && \
    bsdtar -C /dmiso -xf "$iso_path" && \
    chown -R dmdba:dinstall /home/dmdba /dmiso /dmdata && \
    chmod -R 755 "$DM_DATA_DIR" "$DM_ARCH_DIR" "$DM_BAK_DIR" && \
    chmod +x /entrypoint.sh && \
    rm -rf /tmp/dm8.zip /tmp/dm8_extract

# 容器入口需要以 root 修复挂载卷权限和执行官方 root 配置脚本，
# 实际安装、初始化和数据库进程会在 entrypoint 中切换到 dmdba。
USER root
WORKDIR /home/dmdba

# 暴露达梦数据库默认监听端口。
EXPOSE 5236

# 容器启动时执行入口脚本，负责首次安装、初始化和启动数据库。
ENTRYPOINT ["/entrypoint.sh"]
