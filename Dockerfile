# 基础镜像：Debian 12 slim（稳定、轻量）-run ok on aliyun pod
FROM --platform=linux/amd64 debian:bookworm-slim

# 维护者信息
LABEL maintainer="your-name <your-email@example.com>"

# ========== 可配置参数（编译时通过--build-arg修改）==========
ARG SQUID_GIT_REPO="https://github.com/squid-cache/squid.git"
ARG SQUID_GIT_BRANCH="SQUID_7_4"
# 核心新增：--enable-heap-replacement 启用GDSF/LFUDA策略
ARG SQUID_CONFIGURE_ARGS="--prefix=/usr/local/squid \
                          --sysconfdir=/etc/squid \
                          --localstatedir=/var \
                          --with-default-user=squid \
                          --enable-ssl-crtd \
                          --with-openssl \
                          --enable-http2 \
                          --enable-range-offset-limits \
                          --disable-arch-native \
                          --disable-debug \
                          --enable-heap-replacement"  # 新增这行！
ARG CONF_GIT_REPO="https://github.com/itbird2020/squid.git"
ARG CONF_GIT_BRANCH="master"
ARG CONF_GIT_PATH="squid.conf"

# ========== 安装编译依赖 ==========
RUN set -eux; \
    cp /etc/apt/sources.list /etc/apt/sources.list.bak; \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm main contrib non-free" > /etc/apt/sources.list; \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian/ bookworm-updates main contrib non-free" >> /etc/apt/sources.list; \
    echo "deb [trusted=yes] http://mirrors.aliyun.com/debian-security/ bookworm-security main contrib non-free" >> /etc/apt/sources.list; \
    apt update -o Acquire::Check-Valid-Until=false -o APT::Get::AllowUnauthenticated=true; \
    apt install -y --no-install-recommends \
    gcc g++ make autoconf automake libtool libtool-bin libltdl-dev pkg-config \
    openssl libssl-dev libxml2-dev libcap-dev libpng-dev zlib1g-dev \
    git bind9-host procps ca-certificates curl; \
    apt clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*;

# ========== 创建目录 + 用户组 ==========
RUN set -eux; \
    mkdir -p /opt/squid/source /usr/local/squid /var/log/squid /var/run/squid /var/spool/squid /etc/squid; \
    if ! getent group squid; then groupadd -r squid; fi; \
    if ! getent passwd squid; then useradd -r -g squid -d /var/spool/squid -s /sbin/nologin squid; fi; \
    chown -R squid:squid /var/log/squid /var/run/squid /var/spool/squid /etc/squid; \
    chmod 755 /var/log/squid /var/run/squid /var/spool/squid;

# ========== 拉取源码 + 编译安装（核心步骤）==========
RUN set -eux; \
    if [ -n "$SQUID_GIT_REPO" ]; then \
        cd /opt/squid/source && \
        git clone -b $SQUID_GIT_BRANCH $SQUID_GIT_REPO ./squid-src && \
        cd ./squid-src && \
        export LIBTOOL=/usr/bin/libtool && \
        export LIBTOOLIZE=/usr/bin/libtoolize && \
        ./bootstrap.sh && \
        ./configure $SQUID_CONFIGURE_ARGS && \
        make -j$(nproc) && \
        make install && \
        make clean && \
        rm -rf /opt/squid/source; \
    fi

# ========== 替换配置文件（可选）==========
RUN set -eux; \
    if [ -n "$CONF_GIT_REPO" ]; then \
        cd /tmp && git clone -b $CONF_GIT_BRANCH --depth=1 $CONF_GIT_REPO ./conf-repo && \
        cp -f /tmp/conf-repo/$CONF_GIT_PATH /etc/squid/squid.conf && \
        /usr/local/squid/sbin/squid -k parse && \
        rm -rf /tmp/conf-repo; \
    fi

# ========== 系统配置 ==========
EXPOSE 3128/tcp
ENV PATH="/usr/local/squid/sbin:$PATH"

# ========== 空CMD（启动逻辑交给docker run）==========
CMD ["echo", "Squid compiled successfully. Use docker run to start."]
