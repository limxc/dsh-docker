#!/bin/sh
set -e

# 首启联网装 3 插件
if [ ! -f "/data/.dsh-plugins" ]; then
  echo "[entrypoint] 首次启动：安装插件（webui + auth-gate + market）..."
  dsh plugin --profile web add dsh-auth-gateway
  dsh plugin --profile web add @linxin666/dsh-web-ui-all
  dsh plugin --profile web add dshmarket
  dsh --version > "/data/.dsh-plugins"
fi

exec dsh web --port 3080