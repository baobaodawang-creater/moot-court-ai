# 部署指南（六步零报错 SOP）

本文档基于一次完整的故障复盘整理，目标是在新机器上一次部署通过。

## 前置条件

- Docker Engine / Docker Desktop 24+
- `docker compose` v2
- 可访问：
  - `api.deepseek.com`
  - `dashscope.aliyuncs.com`
  - `ghcr.io`

---

## 六步零报错部署 SOP

### Step 1：宿主机预建目录并预置权限（防挂载权限坑）

不要让 Docker 在挂载时自动创建目录。先在宿主机创建目录并赋予 UID `1000`（容器 `node` 用户）：

```bash
mkdir -p ~/moot-court-test/.openclaw/workspace
mkdir -p ~/moot-court-test/.openclaw/agents/{clerk,plaintiff,defendant,judge}/agent
mkdir -p ~/moot-court-test/workspace/agents/{clerk,plaintiff,defendant,judge}/workspace/evidence
mkdir -p ~/moot-court-test/workspace/agents/judge/workspace/templates

sudo chown -R 1000:1000 ~/moot-court-test
```

### Step 2：预置合规配置文件（防 Schema Fail-Safe）

在容器启动前准备好配置文件：

- `~/.openclaw/openclaw.json`：使用仓库中的 [openclaw.json](/Users/lihaochen/openclaw/workspace/moot-court-ai/openclaw.json)
- 每个 Agent 的 `auth-profiles.json`：使用占位符 `${DEEPSEEK_API_KEY}` / `${DASHSCOPE_API_KEY}` 模板

本仓库中的模板文件可直接复制：

- [agents/clerk/agent/auth-profiles.json](/Users/lihaochen/openclaw/workspace/moot-court-ai/agents/clerk/agent/auth-profiles.json)
- [agents/plaintiff/agent/auth-profiles.json](/Users/lihaochen/openclaw/workspace/moot-court-ai/agents/plaintiff/agent/auth-profiles.json)
- [agents/defendant/agent/auth-profiles.json](/Users/lihaochen/openclaw/workspace/moot-court-ai/agents/defendant/agent/auth-profiles.json)
- [agents/judge/agent/auth-profiles.json](/Users/lihaochen/openclaw/workspace/moot-court-ai/agents/judge/agent/auth-profiles.json)

### Step 3：启动容器

可选两种方式：

1. 使用 `docker run`（复盘原始流程）：

```bash
docker run -d \
  --name moot-court-test \
  -p 18899:18789 \
  -v ~/moot-court-test/.openclaw:/home/node/.openclaw \
  -v ~/moot-court-test/workspace:/home/node/moot-court-ai \
  --env-file ~/moot-court-test/.env \
  -e OPENCLAW_TZ=Asia/Shanghai \
  ghcr.io/openclaw/openclaw:latest
```

2. 使用本仓库 `docker compose`：

```bash
docker compose up -d
```

### Step 4：安装 Lobster 依赖

如果镜像内未安装 Lobster，执行：

```bash
docker exec -u root moot-court-test npm install -g @openclaw/lobster
```

说明：本仓库的 [docker-compose.yml](/Users/lihaochen/openclaw/workspace/moot-court-ai/docker-compose.yml) 已加入容器启动时自动安装 `@openclaw/lobster`，此步骤通常可跳过。

### Step 5：Web 控制台设备授权

```bash
docker exec moot-court-test openclaw devices list
docker exec moot-court-test openclaw devices approve <你的RequestID>
```

### Step 6：下发案件物料并清 Session 缓存

每次替换案件材料、角色提示词或证据后，建议清理 session 再重启：

```bash
docker exec moot-court-test sh -c "rm -rf /home/node/.openclaw/agents/*/sessions"
docker restart moot-court-test
```

---

## 运行庭审（命令行）

在仓库目录执行：

```bash
./scripts/init-case.sh test-cases/contract-dispute/
./scripts/run-trial.sh contract-dispute
```

输出目录：

- `output/*-judgment-*.md`：判决书
- `output/*-raw-*.log`：完整原始日志

---

## 安全说明

- 仓库内配置文件只允许使用环境变量占位符，不应提交真实密钥。
- 推荐将真实密钥仅放在 `.env`（已被 `.gitignore` 忽略）。
- 不要把 Gateway 直接暴露到公网。
