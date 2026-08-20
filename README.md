# dsh-docker

**DeepSeek Harness（dsh）+ [dsh-web-ui](https://github.com/zhu1090093659/dsh-web-ui) 全家桶 + [dsh-auth-gateway](https://github.com/xbzbing/dsh-auth-gateway) 登录门禁 + [dsh-market](https://github.com/dsh-market/dsh-market) 插件市场的 Docker 一键部署**，GitHub Actions 每日自动检查 dsh 上游更新、构建并推送 Docker Hub。插件在容器首次启动时安装到持久化数据目录。

```
┌────────────────────────────── 单容器 ──────────────────────────────┐
│ tini (init:true)                                                   │
│   └── dsh web --port 3080                                          │
│       ├── dsh-auth-gateway 登录门禁                                │
│       └── dsh-web-ui / dsh-market 等插件                           │
└─────────────────────────────────────────────────────────────────────┘
         ▲ 宿主机端口映射 3080:3080
         │ 浏览器 → 登录页 → 设置个人密码 → 会话 Cookie
```

- **dsh-auth-gateway 登录门禁**：dsh 自身没有任何认证且 API 可执行代码，门禁补齐认证面——网关独占对外端口、内部 webserver 钉回环不可绕过；密码 scrypt 哈希 + 源锁定/全局限速防爆破 + HttpOnly 会话（详见下方「安全说明」）
- **dsh-market 插件市场**：Web 设置 → 插件市场，一键安装 / 升级 / 禁用插件。**日常插件升级无需改镜像 / 重建容器**
- **每日 02:00（北京时间）自动检查** npm 上游 `@deepseek-ai/dsh`，有更新则构建、推送 Docker Hub、回写版本号
- **无 .env 文件**：全部配置直接改 `docker-compose.yml`
- **数据持久化**：配置 / 凭据 / 插件 profile 保存到 `./data`，agent 工作区保存到 `./workspace`

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

升级后插件 profile 保存在 `./data` 中，不会因镜像更新自动重置；插件版本可在 dsh-market 中单独升级。

### 插件升级（日常，无需动镜像）

Web 设置 → 插件市场（dsh-market）→ 一键升级 webui / 门禁 / 任意插件。升级结果写入 `./data`，重启保留。

### 本地构建（维护者）

本地构建使用独立的 `docker-compose.build.yml`，不会修改面向用户的 Docker Hub 拉取配置：

```sh
docker compose -f docker-compose.build.yml up -d --build
```

本地镜像标签为 `dsh-docker:local`。停止容器：

```sh
docker compose -f docker-compose.build.yml down
```

也可以直接使用 Dockerfile 构建，默认安装 dsh 最新版：

```sh
docker build -t dsh-docker:latest .
```

需要钉住特定版本（可复现构建）时，显式传 `--build-arg`：

```sh
docker build \
  --build-arg DSH_VERSION=0.1.0-rc.7 \
  -t dsh-docker:latest .
```

> 镜像构建时只安装 dsh 和 pnpm；插件（webui / gate / market）在首次启动时按 npm latest 安装到 `./data/profiles/web`，之后由 dsh-market 管理。CI（build-publish.yml）默认查 npm latest 作为 `--build-arg`（`versions.json` 仅兜底；check-updates 触发时显式传新版本），镜像 tag 为 `latest` 与 `<dsh版本>`。

本地构建镜像会安装 pnpm 11，并在首次启动前为 `cloudflared`、`cpu-features`、`node-pty`、`ssh2` 开放原生构建脚本；入口脚本还会清理 task-board 遗留进程锁，避免容器重启时因 PID 复用启动失败。

---

## 配置（全部在 docker-compose.yml 中）

| 项            | 默认                      | 说明                                                          |
| ------------- | ------------------------- | ------------------------------------------------------------- |
| `image`       | `limxc/dsh-docker:latest` | 镜像；固定版本把 `latest` 改为 `<dsh版本>`（如 `0.1.0-rc.7`） |
| `ports`       | `3080:3080`               | 左侧为宿主机对外端口（dsh-auth-gateway 登录网关）             |
| `extra_hosts` | 未配置                    | 按需添加，用于允许 agent 访问宿主机网络服务                   |

**没有密码环境变量**：门禁的初始密码由 dsh-auth-gateway 首次启动时自动生成并打印到容器日志（`docker logs dsh`），首次登录强制引导设置个人密码，密码存于 `./data/auth-gate/`。忘记密码可用容器内 `/data/profiles/web/node_modules/.bin/dsh-auth-gateway-reset` 删除密码记录，**然后重启容器**，新初始密码会重新生成并打印到日志。

### 门禁可选配置

在数据卷 `profiles/web/cordis.patch.yml` 里 `dsh-auth-gateway` 行的 `config` 下覆盖（参考 [dsh-auth-gateway README](https://github.com/xbzbing/dsh-auth-gateway)）：

| 字段                               | 默认               | 说明                                                  |
| ---------------------------------- | ------------------ | ----------------------------------------------------- |
| `listenHost` / `listenPort`        | `0.0.0.0` / `3080` | 网关对外监听                                          |
| `maxLoginFailures` / `lockMinutes` | `5` / `5`          | 密码失败锁定阈值与时长                                |
| `maxGlobalAuthAttemptsPerMinute`   | `60`               | 全局登录尝试速率上限                                  |
| `otpRequired`                      | `false`            | TOTP 双因素（默认关闭；在「认证设置」中按需绑定启用） |

### agent 访问宿主机服务（默认禁用）

当前 compose 未配置 `extra_hosts`。如需访问宿主机服务，在对应 compose 的 `dsh` 服务下添加：

```yaml
extra_hosts:
    - "host.docker.internal:host-gateway"
```

之后容器内可通过 `host.docker.internal` 访问宿主机上监听非 loopback 的服务。

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

| 文件                | 触发                                   | 行为                                                                            |
| ------------------- | -------------------------------------- | ------------------------------------------------------------------------------- |
| `check-updates.yml` | 每日 02:00（北京时间）/ 手动           | 查 dsh 上游版本 → 有更新 → 调 build-publish → 成功后回写 `versions.json` 并提交 |
| `build-publish.yml` | push master（相关文件）/ 手动 / 被调用 | 多架构构建（amd64+arm64）→ 推送 Docker Hub                                      |

镜像 tag：`latest`、`<dsh版本>`（如 `0.1.0-rc.7`）。

### 配置（仓库 Settings → Secrets and variables → Actions）

| 名称                 | 类型             | 说明                                     |
| -------------------- | ---------------- | ---------------------------------------- |
| `DOCKERHUB_USERNAME` | Secret           | Docker Hub 用户名                        |
| `DOCKERHUB_TOKEN`    | Secret           | Docker Hub Access Token（读写）          |
| `DOCKERHUB_REPO`     | Variable（可选） | 镜像仓库名，默认 `<用户名>/dsh-docker`   |
| `PLATFORMS`          | Variable（可选） | 构建平台，默认 `linux/amd64,linux/arm64` |

改检查时间：编辑 `check-updates.yml` 的 cron（UTC 表达；北京时间 02:00 = UTC 18:00，即 `0 18 * * *`）。

---

## 避坑记录

1. **首次启动可能较慢**：插件安装和 node-gyp 编译会在首次启动时运行，等待容器健康检查通过即可。
2. **`ERR_PNPM_IGNORED_BUILDS`**：入口脚本会在插件安装前为 `cloudflared`、`cpu-features`、`node-pty`、`ssh2` 写入 `allowBuilds: true`；不要把该配置改回占位文本。
3. **插件 profile 位于数据目录**：插件安装在 `/data/profiles/web`，宿主机对应 `./data/profiles/web`；删除 `./data` 会同时删除插件、认证和其他持久化数据。
4. **task-board 锁残留**：入口脚本会在 dsh 启动前清理 `/data/task-board/ledger-v2.lock`，只删除进程锁，不删除 `ledger-v2.json` 任务数据。
5. **工作区挂载权限**：当前 compose 使用 bind mount；宿主机目录权限不合适时，容器内 agent 可能无法写入，请为挂载目录提供读写权限。
6. **容器初始化**：compose 的 `init: true` 使用 tini 回收孤儿进程。

---

## 项目结构

```
dsh-docker/
├── Dockerfile                    # dsh + pnpm 运行镜像
├── docker-compose.yml            # 面向用户的单服务编排（直接拉 Docker Hub 镜像）
├── docker-compose.build.yml      # 本地构建并运行
├── entrypoint.sh                 # 首启安装插件 / pnpm 配置 / 锁清理
├── versions.json                 # dsh 版本单一事实来源（CI 读写）
├── scripts/                      # CI 脚本（check-updates / bump-versions / resolve-versions）
└── .github/workflows/
    ├── check-updates.yml         # 每日 02:00 检查 → 构建 → 回写版本
    └── build-publish.yml         # 构建并推送 Docker Hub
```

## 许可证

[MIT](LICENSE)。上游：dsh 为 deepseek-ai（MIT），dsh-web-ui 为 zhu1090093659（Apache-2.0），dsh-auth-gateway 为 xbzbing（MIT），dsh-market 为 dsh-market（MIT），本仓库仅做 Docker 编排与打包。
