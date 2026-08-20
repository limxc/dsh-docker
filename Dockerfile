# DeepSeek Harness (dsh) Web UI - Docker 镜像
# 说明:不锁版本,每次构建都安装 npm 上的最新版 @deepseek-ai/dsh
FROM node:24-slim
ARG DSH_VERSION=latest

# 基础工具:git(工作区操作)、curl(健康检查)、vim
# python3/make/g++ 用于编译 node-pty 等原生模块(node-gyp 必需)
RUN apt-get update \
    && apt-get install -y --no-install-recommends git curl vim ca-certificates python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @deepseek-ai/dsh@${DSH_VERSION}


# 数据目录:配置、凭据、插件 profile、会话都存这里(compose 把 dsh-home 卷挂到 /data)
ENV DSH_HOME=/data
RUN mkdir -p /data /workspace

# dsh 的启动目录就是默认工作区
WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3080

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -fsS http://127.0.0.1:3080/ >/dev/null || exit 1

ENTRYPOINT ["entrypoint.sh"]