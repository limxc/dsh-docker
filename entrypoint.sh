#!/bin/sh
set -e

# 首启联网装 3 插件
if [ ! -f "/data/.dsh-plugins" ]; then
  echo "[entrypoint] 首次启动：安装插件（webui + auth-gate + market）..."
  profile_dir="${DSH_HOME}/profiles/web"
  pnpm_workspace="${profile_dir}/pnpm-workspace.yaml"
  mkdir -p "${profile_dir}"
  if [ ! -f "${pnpm_workspace}" ]; then
    printf '%s\n' \
      'packages:' \
      '  - .' \
      '' \
      'nodeLinker: hoisted' \
      'autoInstallPeers: false' \
      'allowBuilds:' \
      '  cloudflared: true' \
      '  cpu-features: true' \
      '  node-pty: true' \
      '  ssh2: true' > "${pnpm_workspace}"
  else
    sed -i -E \
      's/^(  (cloudflared|cpu-features|node-pty|ssh2):).*/\1 true/' \
      "${pnpm_workspace}"
  fi
  dsh plugin --profile web add dsh-auth-gateway
  dsh plugin --profile web add @linxin666/dsh-web-ui-all
  dsh plugin --profile web add dshmarket
  dsh --version > "/data/.dsh-plugins"
fi

# 容器重启后旧 PID 可能复用，清理 task-board 的遗留进程锁。
rm -f "${DSH_HOME}/task-board/ledger-v2.lock"

exec dsh web --port 3080