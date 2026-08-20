# dsh-docker

**DeepSeek Harness（dsh）+ [dsh-web-ui](https://github.com/zhu1090093659/dsh-web-ui) 全家桶 + [dsh-auth-gateway](https://github.com/xbzbing/dsh-auth-gateway) 登录门禁 + [dsh-market](https://github.com/dsh-market/dsh-market) 插件市场的 Docker 一键部署**，GitHub Actions 每日自动检查 dsh 上游更新、构建并推送 Docker Hub。

```
┌────────────────────────────────────── 单容器 ──────────────────────────────────────┐
│                                                                                     │
│  tini (PID 1，init:true)                                                            │
│   └── supervisord                                                                   │
│        └── dsh   (node)  --port 3080                                                 │
│             ├── dsh-auth-gateway 网关  0.0.0.0:3080  ← 登录门禁（唯一入口）          │
│             │      未认证 /api → 401 ｜ 页面 → 302 登录页 ｜ WS → 拒绝               │
│             └── dsh webserver         127.0.0.1:3081  ← 内部回环，外部不可达        │
│                                                                                     │
│  预装插件：dsh-web-ui-all（全家桶）· dsh-auth-gateway（门禁）· dsh-market（插件市场）   │
└─────────────────────────────────────────────────────────────────────────────────────┘
         ▲ 宿主机端口映射 3080:3080
         │ 浏览器 ── 未认证 302 → 登录页 → 设置个人密码 → 会话 Cookie（默认 30 天）
```

- **dsh-auth-gateway 登录门禁**：dsh 自身没有任何认证且 API 可执行代码，门禁补齐认证面——网关独占对外端口、内部 webserver 钉回环不可绕过；密码 scrypt 哈希 + 源锁定/全局限速防爆破 + HttpOnly 会话（详见下方「安全说明」）
- **dsh-market 插件市场**：Web 设置 → 插件市场，一键安装 / 升级 / 禁用所有插件（含预装的 webui、门禁本身）。**日常插件升级无需改镜像 / 重建容器**
- **每日 02:00（北京时间）自动检查** npm 上游 `@deepseek-ai/dsh`，有更新则构建、推送 Docker Hub、回写版本号
- **无 .env 文件**：全部配置直接改 `docker-compose.yml`
- **数据持久化**：配置 / 凭据（密码哈希、OTP 密钥，`dsh-home` 卷）与 agent 工作区（`workspace-data` 卷）

---

## 快速开始

### 快速开始（使用 Docker Hub 预构建镜像）

```sh
docker compose up -d
```

浏览器打开 `http://<主机IP>:3080`：

1. **首次访问会自动跳转登录页**，初始密码打印在容器日志里：
   ```sh
   docker logs dsh | grep -i '初始密码\|initial password'
   ```
2. 用初始密码登录后，会进入**引导页强制设置个人密码**（至少 8 位、大小写混合或含特殊字符；初始密码一次性，设置后失效）。
3. 之后进入 dsh Web UI，填入模型 API Key 即可使用。登录态为会话 Cookie（默认 30 天）。**注意：会话保存在进程内存中（不落盘），容器重启后需重新登录**（密码与 OTP 数据不受影响）。

固定镜像版本：把 `docker-compose.yml` 里 `image: limxc/dsh-docker:latest` 的 `latest` 改成 `<dsh版本>`（如 `0.1.0-rc.7`）。

### 更新

```sh
docker compose pull && docker compose up -d
```

升级后首启，entrypoint 会把插件刷新到镜像内置版本。**注意**：dsh 镜像升级会整体重铺插件 profile——若之前用 dsh-market 升级过插件，会重置回镜像内置版本，需在 dsh-market 里重新升级。

### 插件升级（日常，无需动镜像）

Web 设置 → 插件市场（dsh-market）→ 一键升级 webui / 门禁 / 任意插件。升级结果写入数据卷 `dsh-home`，重启保留。

### 本地构建（维护者）

compose 面向用户直接拉取镜像，不负责构建。维护者需手动构建时，默认装 dsh 最新版：

```sh
docker build -t dsh-docker:latest .
```

需要钉住特定版本（可复现构建）时，显式传 `--build-arg`：

```sh
docker build \
  --build-arg DSH_VERSION=0.1.0-rc.7 \
  -t dsh-docker:latest .
```

> 插件（webui / gate / market）构建期按 npm latest 预装，升级由 dsh-market 管理，镜像不追踪其版本。CI（build-publish.yml）默认查 npm latest 作为 `--build-arg`（`versions.json` 仅兜底；check-updates 触发时显式传新版本），镜像 tag 为 `latest` 与 `<dsh版本>`。

---

## 配置（全部在 docker-compose.yml 中）

| 项 | 默认 | 说明 |
| --- | --- | --- |
| `image` | `limxc/dsh-docker:latest` | 镜像；固定版本把 `latest` 改为 `<dsh版本>`（如 `0.1.0-rc.7`） |
| `ports` | `3080:3080` | 左侧为宿主机对外端口（dsh-auth-gateway 登录网关） |
| `TZ` | `Asia/Shanghai` | 容器时区 |
| `extra_hosts` | 注释（禁用） | 允许 agent 访问宿主机网络服务（按需开启） |

**没有密码环境变量**：门禁的初始密码由 dsh-auth-gateway 首次启动时自动生成并打印到容器日志（`docker logs dsh`），首次登录强制引导设置个人密码，密码存于数据卷 `$DSH_HOME/auth-gate/`。忘记密码可用容器内 `~/.dsh/profiles/web/node_modules/.bin/dsh-auth-gateway-reset` 删除密码记录，**然后重启容器**，新初始密码会重新生成并打印到日志。

### 门禁可选配置

在数据卷 `profiles/web/cordis.patch.yml` 里 `dsh-auth-gateway` 行的 `config` 下覆盖（参考 [dsh-auth-gateway README](https://github.com/xbzbing/dsh-auth-gateway)）：

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `listenHost` / `listenPort` | `0.0.0.0` / `3080` | 网关对外监听 |
| `maxLoginFailures` / `lockMinutes` | `5` / `5` | 密码失败锁定阈值与时长 |
| `maxGlobalAuthAttemptsPerMinute` | `60` | 全局登录尝试速率上限 |
| `otpRequired` | `false` | TOTP 双因素（默认关闭；在「认证设置」中按需绑定启用） |

### agent 访问宿主机服务（默认禁用）

默认禁用（compose 里已注释）。启用：取消 `docker-compose.yml` 里 `extra_hosts` 那段注释，容器内即可用 `host.docker.internal` 连宿主机上监听非 loopback 的服务。

### 公网 HTTPS

镜像 / 容器内不再承担 TLS——**HTTPS 由你已有的外部 nginx 终结**，反代到宿主机 3080 端口即可（HTTP/1.1 + WebSocket 转发必需项与之前相同）：

```nginx
server {
    listen 443 ssl;
    server_name dsh.example.com;
    # ssl_certificate ...; ssl_certificate_key ...;

    location / {
        proxy_pass http://<宿主IP>:3080;
        proxy_http_version 1.1;                # ★ 必须（默认 1.0 会断 WS）
        proxy_set_header Upgrade $http_upgrade;        # ★ WS 必需
        proxy_set_header Connection "upgrade";         # ★ WS 必需
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 3600s;
        proxy_buffering off;
    }
}
```

> 门禁按"所有访问一律认证"设计（登录页对公网/内网一视同仁），认证后网关会把请求改写为回环转发给内部 webserver，**信任围栏 / 特权 API（`settings.*`/`credentials.*`）全部放行**，无需任何 Host/Origin 配置。

---

## GitHub Actions 自动更新流水线

### 工作流

| 文件 | 触发 | 行为 |
| --- | --- | --- |
| `check-updates.yml` | 每日 02:00（北京时间）/ 手动 | 查 dsh 上游版本 → 有更新 → 调 build-publish → 成功后回写 `versions.json` 并提交 |
| `build-publish.yml` | push master（相关文件）/ 手动 / 被调用 | 多架构构建（amd64+arm64）→ 推送 Docker Hub → 冒烟测试（网关 302 登录页） |

镜像 tag：`latest`、`<dsh版本>`（如 `0.1.0-rc.7`）。

### 配置（仓库 Settings → Secrets and variables → Actions）

| 名称 | 类型 | 说明 |
| --- | --- | --- |
| `DOCKERHUB_USERNAME` | Secret | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Secret | Docker Hub Access Token（读写） |
| `DOCKERHUB_REPO` | Variable（可选） | 镜像仓库名，默认 `<用户名>/dsh-docker` |
| `PLATFORMS` | Variable（可选） | 构建平台，默认 `linux/amd64,linux/arm64` |

改检查时间：编辑 `check-updates.yml` 的 cron（UTC 表达；北京时间 02:00 = UTC 18:00，即 `0 18 * * *`）。

---

## 安全说明

- **认证由 dsh-auth-gateway 网关承担**：网关独占 `0.0.0.0:3080`，内部 webserver 经 bundle patch 钉在回环 `127.0.0.1:3081`（外部不可达），不存在绕过门禁直连后端的路。未认证 `/api/*` → 401、页面 → 302 登录页、WebSocket 握手直接拒绝。
- **密码安全**：scrypt 哈希存储；**源锁定**（默认 5 次失败/5 分钟）+ **全局速率限制**（默认 60 次/分钟）；登录洪峰在 libuv 线程池异步执行，不阻塞事件循环。
- **会话**：256-bit 随机 token（默认 30 天），HttpOnly + SameSite=Strict Cookie；修改密码 / 禁用 2FA 会吊销全部会话。**会话表为内存态（MVP 取舍，不落盘）**——容器/进程重启后所有人需重新登录，密码与 OTP 数据不受影响。
- **2FA（可选）**：TOTP 默认关闭；需要时在 Web「认证设置」中按需绑定（OTP 密钥 AES-256-GCM 加密落盘，含一次性备份码）。
- **首次部署**：初始密码只打印一次在容器日志（`docker logs dsh`），首次登录强制设置个人密码，初始密码随即作废。公网部署请确保外部 nginx 为 HTTPS（防止密码 / Cookie 明文传输）。
- 默认工作区为 named volume，不触碰宿主机文件系统；改用 bind mount 时只挂专用目录，绝不挂敏感路径。
- agent 运行在容器内（非 root，无特权），宿主机隔离由 Docker 边界提供。

---

## 避坑记录（来自社区项目的已知问题，本仓库均已规避）

1. **dsh web 不支持 `--host 0.0.0.0`**（官方安全护栏）→ 由 dsh-auth-gateway 网关独占对外端口，内部 webserver 钉回环。
2. **浏览器信任围栏 / 特权 API**：`/api` 校验 Host、`settings.*`/`credentials.*` 只接受 loopback，且明文请求带非 loopback Host 会被强制 302 到 https → 网关认证后改写 Host/Origin 为回环转发，信任围栏放行。
3. **`--trusted-host` CLI 不可靠**（rc.6 实测）→ 本方案无需受信 Host：网关统一改写，`DSH_TRUSTED_HOSTS` 配置退役。
4. **npm 11 默认不跑 install 脚本**：dsh 依赖 koffi / node-pty / protobufjs 等原生模块 → `--allow-scripts` 显式放行，构建阶段保留 `build-essential`（prebuild 未命中时 node-gyp 兜底）。
5. **COPY 解引用 symlink**：直接复制 `bin/dsh` 会导致 ESM 依赖解析失败 → 复制 node_modules 后在 RUN 中重建符号链接。
6. **dsh web 需要 `node --expose-internals`** 启动（profile boot 后挂载 HMR watcher）→ supervisord 命令显式带此 flag。
7. **pnpm 11 的 24 小时版本门禁**（dsh-web-ui issue #71）：新版本发布 24h 内会被静默隔离装到旧版，旧版皮肤中心导致 `ERR_MODULE_NOT_FOUND` 崩溃 → profile 的 `pnpm-workspace.yaml` 预置 `minimumReleaseAge: 0` + `minimumReleaseAgeExclude: ['@linxin666/*']`。
8. **`ERR_PNPM_IGNORED_BUILDS`**：cloudflared / cpu-features / ssh2 的 install 脚本被 pnpm 拒绝 → 预置 `onlyBuiltDependencies`（pnpm 10.34 实测，`allowBuilds` 键名已不生效）。
9. **严格布局 `Cannot find package`**：dsh-web-ui-all 的 patch 引用多个子包，pnpm isolated 布局收进嵌套目录 → `nodeLinker: hoisted`。
10. **挂新数据卷后预装插件"消失"**（插件装在 DSH_HOME 下，被卷遮蔽）→ 镜像内 staging + entrypoint 按 dsh 版本标记同步。
11. **supervisord 缺 socket/rpcinterface 配置** → `supervisorctl status` 报错；已按 Debian 默认路径配好。
12. **basic auth 反复 401 弹框**（旧 Caddy 方案）→ 门禁改为登录页 + 会话 Cookie，后台轮询 / PWA 子资源不再触发浏览器原生弹窗；旧方案的路径豁免清单已随 Caddy 整体移除。
13. **健康检查误判**：直接探 dsh 端口会把 401/502 当健康 → 探网关，未认证 302（→登录页）即健康；`start_period: 240s` 覆盖首启初始化。
14. **僵尸进程**：agent 会产生孤儿子进程 → compose `init: true`（tini）。
15. **bind mount 属主问题**：宿主机目录属主非 uid 1000 时 agent 无法写 → 默认 named volume（继承镜像属主），bind mount 需自行 `chown 1000:1000`。
16. **GITHUB_TOKEN 推送不触发 push 事件**（递归保护）→ 单一工作流"先构建推送、后回写版本"，不依赖提交触发。

---

## 项目结构

```
dsh-docker/
├── Dockerfile                    # 三阶段：dsh 安装 → 插件预装（webui + gate + market）→ 运行镜像
├── docker-compose.yml            # 面向用户的单服务编排（直接拉 Docker Hub 镜像，无 .env / build）
├── entrypoint.sh                 # 首启初始化 / 属主修正 / 插件按 dsh 版本同步
├── supervisord.conf              # dsh 进程管理（门禁网关随 dsh 进程内运行，无独立进程）
├── versions.json                 # dsh 版本单一事实来源（CI 读写）
├── profiles/pnpm-workspace.yaml  # 插件安装的 pnpm 预设（避坑 7/8/9）
├── defaults/                     # settings.yaml / AGENTS.md 首启模板
├── scripts/                      # CI 脚本（check-updates / bump-versions / resolve-versions）
└── .github/workflows/
    ├── check-updates.yml         # 每日 02:00 检查 → 构建 → 回写版本
    └── build-publish.yml         # 构建 + 推送 Docker Hub + 冒烟测试
```

## 许可证

[MIT](LICENSE)。上游：dsh 为 deepseek-ai（MIT），dsh-web-ui 为 zhu1090093659（Apache-2.0），dsh-auth-gateway 为 xbzbing（MIT），dsh-market 为 dsh-market（MIT），本仓库仅做 Docker 编排与打包。

## 鸣谢

感谢上述社区 Docker 项目的公开实践，尤其是 Xidong-AI 与 runzhliu 两个项目对 loopback 围栏与 native 模块问题的系统化总结。