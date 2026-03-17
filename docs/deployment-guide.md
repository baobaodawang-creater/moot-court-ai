# 部署指南

本文档面向负责在律所内部署 Moot Court AI 系统的技术人员。

## 部署方式选择

| 方式 | 适合场景 | 难度 |
|------|---------|------|
| Docker (推荐) | 生产环境、多人使用 | ⭐⭐ |
| 本地安装 | 个人试用、开发调试 | ⭐⭐⭐ |

---

## 方式一：Docker 部署（推荐）

### 前置条件
- Docker Desktop 或 Docker Engine 24+
- docker compose v2
- 可访问 api.deepseek.com 和 dashscope.aliyuncs.com 的网络

### 步骤

```bash
# 1. 克隆项目
git clone https://github.com/your-org/moot-court-ai.git
cd moot-court-ai

# 2. 配置 API Keys
cp .env.example .env
nano .env   # 填入 DEEPSEEK_API_KEY 和 DASHSCOPE_API_KEY

# 3. 启动
docker compose up -d

# 4. 查看日志确认启动成功
docker compose logs -f --tail 20

# 5. 浏览器访问
# http://localhost:18789
```

### 停止与重启

```bash
docker compose stop          # 停止
docker compose start         # 启动
docker compose restart       # 重启
docker compose down          # 完全停止并移除容器
docker compose down -v       # 停止并清除数据卷（谨慎！会清除记忆库）
```

### 更新

```bash
docker compose pull          # 拉取最新镜像
docker compose up -d         # 重新启动
```

---

## 方式二：本地安装

### 前置条件

```bash
# Node.js 22+
node --version   # 确保 >= 22

# Python 3.10+
python3 --version

# OpenClaw
npm install -g openclaw@latest
openclaw --version
```

### 步骤

```bash
# 1. 克隆项目
git clone https://github.com/your-org/moot-court-ai.git
cd moot-court-ai

# 2. 配置 API Keys
cp .env.example .env
nano .env

# 3. 赋予脚本执行权限
chmod +x scripts/setup.sh scripts/setup-auth.sh scripts/init-case.sh scripts/run-trial.sh

# 4. 初始化 OpenClaw 目录结构
./scripts/setup.sh

# 5. 生成 4 个 agent 的鉴权文件
./scripts/setup-auth.sh

# 6. 分发案件材料（示例案件）
./scripts/init-case.sh test-cases/contract-dispute/

# 7. （可选）构建法律知识库
pip install -r requirements.txt
python3 scripts/ingest-law.py --input ./laws/

# 8. 运行庭审工作流（命令行）
./scripts/run-trial.sh contract-dispute

# 9. 查看输出
# output/contract-dispute-judgment-*.md
# output/contract-dispute-raw-*.log
```

如需 WebChat 交互模式，再单独启动：

```bash
openclaw gateway --port 18789
# 浏览器访问 http://localhost:18789
```

---

## API Key 获取指南

### DeepSeek API Key
1. 访问 https://platform.deepseek.com
2. 注册/登录
3. 进入「API Keys」页面
4. 点击「创建 API Key」
5. 复制 key（格式：`sk-xxxxxxxxxxxxxxxx`）
6. 充值：新用户通常有免费额度，之后按量计费

### 阿里云百炼 API Key
1. 访问 https://bailian.console.aliyun.com
2. 注册阿里云账号并完成实名认证
3. 开通「模型服务灵积」
4. 进入「API-KEY 管理」
5. 创建 API Key（格式：`sk-xxxxxxxxxxxxxxxx`）
6. Qwen 系列模型新用户有免费额度

---

## 网络要求

本系统需要访问以下域名（均为中国大陆可直连，无需 VPN）：

| 域名 | 用途 | 端口 |
|------|------|------|
| api.deepseek.com | DeepSeek API | 443 |
| dashscope.aliyuncs.com | 阿里云百炼 API | 443 |
| ghcr.io | Docker 镜像拉取（仅首次） | 443 |
| huggingface.co 或 hf-mirror.com | Embedding 模型下载（仅首次） | 443 |

> 如果律所网络限制了 huggingface.co，可使用国内镜像：
> ```bash
> export HF_ENDPOINT=https://hf-mirror.com
> python3 scripts/ingest-law.py --input ./laws/
> ```

---

## 安全注意事项

### API Key 安全
- `.env` 文件已在 `.gitignore` 中，不会被提交到 Git
- `auth-profiles.json` 同样在 `.gitignore` 中
- 生产环境建议使用 Docker secrets 或环境变量管理

### 网络安全
- Gateway 默认绑定 `127.0.0.1`（仅本机可访问）
- 如需局域网内多人访问，修改 `openclaw.json` 中 `gateway.bind` 为 `0.0.0.0`
- **不要将 Gateway 暴露到公网**——它是管理界面，拥有完整权限
- 局域网访问建议配合 nginx 反向代理 + HTTPS

### 数据安全
- 案件材料存储在本地文件系统，不上传到任何第三方
- API 调用会将案件内容发送到模型提供商（DeepSeek / 阿里云）
- 如有数据安全顾虑，可考虑本地部署模型（需 GPU 服务器）

---

## 本地模型部署（可选·高级）

如果律所对数据安全要求极高，不允许案件数据发送到外部 API，可以本地部署模型：

### 使用 Ollama

```bash
# 安装 Ollama
curl -fsSL https://ollama.com/install.sh | sh

# 下载模型
ollama pull qwen3:32b          # 需要 ~20GB 显存
ollama pull deepseek-r1:14b    # 需要 ~10GB 显存

# OpenClaw 配置中修改 provider
# baseUrl: http://localhost:11434/v1
# model: qwen3:32b
```

### 硬件要求（本地模型）

| 模型 | 参数量 | 最低显存 | 推荐硬件 |
|------|--------|---------|---------|
| Qwen3-8B | 8B | 6GB | RTX 4060 |
| Qwen3-14B | 14B | 10GB | RTX 4070 |
| Qwen3-32B | 32B | 20GB | RTX 4090 / A5000 |
| DeepSeek-R1-14B | 14B | 10GB | RTX 4070 |

> 本地模型的推理质量会低于云端 API（尤其是法律推理场景），建议仅在数据安全要求极高时使用。

---

## 常见问题

### Q: 启动后 Agent 报 401 错误？
A: auth-profiles.json 格式不对。必须使用 `version/profiles` 结构：
```json
{
  "version": 1,
  "profiles": {
    "provider:default": {
      "type": "api_key",
      "provider": "provider-name",
      "key": "your-key"
    }
  }
}
```
运行 `./scripts/setup-auth.sh` 会自动生成正确格式。

### Q: 执行 run-trial.sh 时提示找不到 lobster 命令？
A: 先确认本机已安装并可执行 OpenClaw/Lobster 相关命令，再重新执行：
```bash
openclaw --version
```
如果你只使用 Docker 模式，可使用 WebChat 触发庭审流程。

### Q: LanceDB 检索报维度错误？
A: 入库和检索必须使用同一 embedding 模型。默认使用 `BAAI/bge-small-zh-v1.5`（512维）。如果 OpenClaw 的 memory-lancedb 插件使用了不同的 embedding，需要在 `openclaw.json` 中配置对齐。

### Q: Lobster 工作流中的 loop 不工作？
A: sub-workflow loop 功能依赖 Lobster 的 PR #20。如果你使用的 OpenClaw 版本尚未合并此 PR，可以：
1. 将 `max_iterations` 设为 1（禁用循环，只跑一轮举证质证）
2. 或手动触发多轮

### Q: 如何修改举证质证的轮数？
A: 编辑 `workflows/moot-court.lobster`，找到 `evidence_rounds` step 的 `loop.max_iterations`，改为你想要的轮数。

### Q: 一次庭审大概花多少钱？
A: 按 DeepSeek 定价，完整庭审（4阶段 + 2轮举证质证）约消耗 50K-100K tokens，成本约 ¥2-5。如果使用 Qwen 的便宜模型，成本更低。
