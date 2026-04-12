# Metapi 运行维护与功能说明手册（含 `update-and-restart.sh`）

> 适用对象：第一次接手 Metapi 的运维/开发同学。  
> 目标：拿到这份文档即可完成部署、日常维护、本地运行、基础二次开发。

---

## 1. 项目是什么

Metapi 是一个“上游中转站聚合层”，把多个 AI 中转站（`new-api`/`one-api`/`one-hub`/`done-hub`/`veloera`/`anyrouter`/`sub2api` 等）统一成一个网关入口，对下游提供 OpenAI/Claude 兼容接口（`/v1/*`）。

核心能力（新同学最常用）：

| 模块 | 作用 | 管理台入口 |
|---|---|---|
| 站点管理 | 管理上游站点 URL、平台类型、状态 | `站点管理` |
| 连接管理 | 管理 Session/API Key/账号令牌 | `连接管理` |
| 路由管理 | 自动/手动路由、权重与故障切换 | `路由管理` |
| 使用日志 | 请求日志、模型映射、错误排查 | `使用日志` |
| 设置 | Token、定时任务、系统代理、通知等 | `设置` |

---

## 2. 你当前使用的部署脚本说明（重点）

你当前用的是仓库根目录脚本：

- `update-and-restart.sh`

该脚本默认行为：

1. 停服务前备份 `docker/data` 到 `docker/data-backup-时间戳.tar.gz`
2. 停止旧容器
3. 默认基于本地源码重新构建镜像并拉起（`BUILD_LOCAL=1`）
4. 自动注入 `AUTH_TOKEN`/`PROXY_TOKEN`/`PORT`/`TZ`/`METAPI_BIND_HOST`
5. 启动后打印 `docker compose ps` 和最近日志

脚本依赖：

- `docker`
- `tar`
- `git`

脚本实际使用的 Compose 文件：

- `docker/docker-compose.yml`
- 本地构建模式额外叠加：`docker/docker-compose.override.yml`

---

## 3. 服务器部署（按你现有脚本）

## 3.1 一次性准备

```bash
git clone https://github.com/cita-777/metapi.git
cd metapi
chmod +x ./update-and-restart.sh
```

先确认依赖：

```bash
docker --version
git --version
tar --version
```

## 3.2 先改脚本中的部署配置

编辑 `update-and-restart.sh` 顶部配置块，至少改这几个变量：

- `METAPI_AUTH_TOKEN`
- `METAPI_PROXY_TOKEN`
- `METAPI_PORT`
- `METAPI_TZ`
- `METAPI_BIND_HOST`

建议：

- `METAPI_AUTH_TOKEN` 和 `METAPI_PROXY_TOKEN` 使用高强度随机值
- 如果只允许本机访问，可把 `METAPI_BIND_HOST` 改为 `127.0.0.1`

## 3.3 执行部署命令（明确可复制）

### 场景 A：用当前本地代码构建并重启（默认）

```bash
./update-and-restart.sh
```

### 场景 B：先 `git pull --rebase` 再部署

```bash
./update-and-restart.sh --pull
```

> 注意：`--pull` 会检查工作区是否干净；有未提交改动会直接退出。

### 场景 C：不本地构建，直接用预构建镜像

```bash
./update-and-restart.sh --use-image
```

### 场景 D：跳过备份（不推荐）

```bash
./update-and-restart.sh --skip-backup
```

### 场景 E：本地构建时安装 kubectl/helm（仅 K3s/Helm 更新中心需要）

```bash
./update-and-restart.sh --with-k8s-tools
```

可叠加参数示例：

```bash
./update-and-restart.sh --pull --use-image
```

## 3.4 部署后验收命令

```bash
docker compose -f docker/docker-compose.yml ps
docker compose -f docker/docker-compose.yml logs --tail 50
```

健康检查：

```bash
curl -sS http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer <你的PROXY_TOKEN>"
```

管理台访问：

- `http://<服务器IP或域名>:4000`
- 登录令牌：脚本中的 `METAPI_AUTH_TOKEN`

---

## 4. 日常维护（命令清单）

## 4.1 查看状态与日志

```bash
docker compose -f docker/docker-compose.yml ps
docker compose -f docker/docker-compose.yml logs -f
docker compose -f docker/docker-compose.yml logs --tail 200
```

## 4.2 重启/停止

```bash
docker compose -f docker/docker-compose.yml restart
docker compose -f docker/docker-compose.yml down
docker compose -f docker/docker-compose.yml up -d
```

> 如果你使用脚本本地构建模式，实际运行的是双文件组合；最稳妥做法是继续统一用脚本重启。

## 4.3 升级建议

优先使用脚本升级：

```bash
./update-and-restart.sh --pull
```

它会自动做备份 + 重启，风险低于手工拼命令。

## 4.4 回滚建议

脚本会生成：

- `docker/data-backup-YYYYMMDD-HHMMSS.tar.gz`

发生严重故障时：

1. `docker compose down`
2. 备份当前 `docker/data`
3. 用备份包恢复 `docker/data`
4. 再 `./update-and-restart.sh --use-image` 或 `docker compose up -d`

---

## 5. 本地运行（含默认 Token）

> 下面是“源码运行（开发/调试）”流程，不是 Docker 成品部署流程。

## 5.1 环境要求

- 当前仓库 `package.json` 要求：`Node.js >= 25.0.0`
- `npm`

## 5.2 使用默认 Token 直接本地启动（Linux/macOS）

```bash
git clone https://github.com/cita-777/metapi.git
cd metapi
npm install
npm run db:migrate
AUTH_TOKEN=change-me-admin-token PROXY_TOKEN=change-me-proxy-sk-token npm run dev
```

访问地址：

- 前端：`http://127.0.0.1:5173`
- 后端：`http://127.0.0.1:4000`
- 管理台登录 token：`change-me-admin-token`

## 5.3 Windows PowerShell 启动（默认 Token）

```powershell
git clone https://github.com/cita-777/metapi.git
cd metapi
npm install
npm run db:migrate
$env:AUTH_TOKEN="change-me-admin-token"
$env:PROXY_TOKEN="change-me-proxy-sk-token"
npm run dev
```

## 5.4 用 `.env` 启动（推荐长期开发）

```bash
cp .env.example .env
# Windows 用 Copy-Item .env.example .env
```

`.env` 中默认值包含：

- `AUTH_TOKEN=change-me-admin-token`
- `PROXY_TOKEN=change-me-proxy-sk-token`
- `PORT=4000`
- `DATA_DIR=./data`

然后运行：

```bash
npm run db:migrate
npm run dev
```

---

## 6. 功能使用最短路径（新同学 15 分钟上手）

1. 登录管理台（`AUTH_TOKEN`）
2. 在 `站点管理` 添加上游站点
3. 在 `连接管理` 添加 Session 或 API Key
4. 在 `账号令牌管理` 同步/创建账号令牌
5. 到 `路由管理` 检查是否自动生成通道
6. 用下游 token 测试 `/v1/models` 与 `/v1/chat/completions`

测试命令示例：

```bash
curl -sS http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer <PROXY_TOKEN>"

curl -sS http://127.0.0.1:4000/v1/chat/completions \
  -H "Authorization: Bearer <PROXY_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"ping"}]}'
```

---

## 7. 二次开发指南（够用版）

## 7.1 关键目录

```text
src/server      # Fastify 后端与代理核心
src/web         # React 管理台
src/desktop     # Electron 桌面壳
scripts/dev     # 开发辅助脚本
docs            # 文档站与运维文档
docker          # Dockerfile 与 compose
```

## 7.2 常用开发命令

```bash
npm run dev
npm run dev:server
npm run build
npm run build:web
npm run build:server
npm run build:desktop
npm test
```

数据库/Schema 相关：

```bash
npm run db:migrate
npm run db:generate
npm run schema:generate
```

## 7.3 提交前最小检查

```bash
npm test
npm run build
```

如果改动了架构边界，补跑：

```bash
npm run repo:drift-check
```

---

## 8. 常见问题与处理

| 问题 | 现象 | 处理命令/动作 |
|---|---|---|
| 脚本 `--pull` 失败 | 提示 worktree 有改动 | 提交/暂存改动后重试 |
| 端口冲突 | `4000` 无法启动 | 改 `METAPI_PORT`（脚本）或释放端口 |
| 登录失败 | `AUTH_TOKEN` 不匹配 | 使用脚本配置值或在设置页更新后用新值 |
| 无可用模型 | `/v1/models` 为空 | 检查站点、连接、令牌同步、路由重建 |
| 同步令牌失败 | 账号过期/站点异常 | 在连接管理重新绑定或刷新站点状态 |

---

## 9. 安全建议（强烈建议执行）

1. 生产环境不要使用默认 token（`change-me-*`）。
2. 不要把 `.env`、备份包、真实 token 提交到 Git。
3. `METAPI_BIND_HOST` 设为 `127.0.0.1` + Nginx/Caddy 反代通常更安全。
4. 升级前保留至少 1 份可用备份（脚本已默认备份，勿随意 `--skip-backup`）。

---

## 10. 附录：你当前脚本对应的标准执行序列

```bash
# 1) 可选：拉代码
git pull --rebase

# 2) 停容器
docker compose -f docker/docker-compose.yml [-f docker/docker-compose.override.yml] down --remove-orphans

# 3) 备份数据
tar -czf docker/data-backup-$(date +%Y%m%d-%H%M%S).tar.gz -C docker/data .

# 4) 启动
# 本地构建模式（默认）
docker compose -f docker/docker-compose.yml -f docker/docker-compose.override.yml up -d --build --force-recreate

# 或预构建镜像模式（--use-image）
docker compose -f docker/docker-compose.yml pull metapi
docker compose -f docker/docker-compose.yml up -d --force-recreate --no-build

# 5) 验收
docker compose -f docker/docker-compose.yml ps
docker compose -f docker/docker-compose.yml logs --tail 20
```

