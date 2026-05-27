# 使用 CentOS 7 作为达梦数据库运行环境的基础镜像。
FROM centos:7

# 设置容器默认中文 UTF-8 语言环境，避免安装和运行时中文乱码。
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8

# 定义达梦数据库安装目录，并将数据库命令加入 PATH。
ENV DM_HOME=/home/dmdba/dmdbms
ENV PATH=$DM_HOME/bin:$PATH

# 拷贝达梦安装包和容器入口脚本到镜像中。
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

# 安装运行依赖、创建达梦运行用户和数据目录，并解压安装包。
RUN yum clean all && \
    yum install -y unzip glibc-common libaio net-tools && \
    localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8 && \
    groupadd dinstall && \
    useradd -g dinstall -m -d /home/dmdba -s /bin/bash dmdba && \
    mkdir -p /dmiso /dmdata/data /dmdata/arch /dmdata/dmbak && \
    unzip /tmp/dm8.zip -d /dmiso && \
    chown -R dmdba:dinstall /home/dmdba /dmiso /dmdata && \
    chmod +x /entrypoint.sh && \
    rm -f /tmp/dm8.zip

# 后续命令以达梦专用用户身份执行，避免使用 root 运行数据库。
USER dmdba
WORKDIR /home/dmdba

# 暴露达梦数据库默认监听端口。
EXPOSE 5236

# 容器启动时执行入口脚本，负责首次安装、初始化和启动数据库。
ENTRYPOINT ["/entrypoint.sh"]
