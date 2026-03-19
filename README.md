# 🏛️ Moot Court AI — 模拟法庭红蓝对抗系统

> 基于 OpenClaw + Lobster 的多 Agent 法庭模拟系统，面向中国律师事务所部署。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-compatible-orange.svg)](https://github.com/openclaw/openclaw)

## 这是什么？

Moot Court AI 是一套**AI 模拟法庭系统**，通过 4 个物理隔离的 AI Agent（书记员、原告律师、被告律师、法官）严格按照《中华人民共和国民事诉讼法》的庭审流程，对案件进行**红蓝对抗式推演**。

律师事务所在正式开庭前，可以用本系统模拟庭审全过程，**提前发现证据链漏洞、预判对方策略、评估胜诉概率**。

## 核心特性

- 🔴🔵 **红蓝对抗**: 原告（红队）和被告（蓝队）各自持有私密证据，互不可见
- 📋 **严格流程**: 完全遵循中国民事庭审程序——诉辩→举证质证→法庭辩论→宣判
- 🔒 **信息隔离**: 原被告 workspace 物理隔离，通过 Lobster 工作流控制信息流向
- ⚖️ **争议焦点**: 法官 Agent 在辩论前自动归纳争议焦点（庭审灵魂步骤）
- 📄 **裁判文书**: 自动生成《模拟民事判决书》和《诉讼风险推演报告》
- 🇨🇳 **纯国产方案**: 全部使用 DeepSeek / Qwen 等国内大模型，无需 VPN

## 模型选型

所有模型均为**中国大陆可直连 API**，无需翻墙：

| Agent | 角色 | 推荐模型 | 备选模型 | 为什么 |
|-------|------|---------|---------|-------|
| clerk | 书记员 | `deepseek-chat` | `qwen-turbo` | 只需格式遵循，用最便宜的 |
| plaintiff | 原告律师 | `deepseek-reasoner` | `qwen-max` | 需要强攻击性逻辑推理 |
| defendant | 被告律师 | `qwen-max` | `deepseek-reasoner` | 需要严密防守与三性质证 |
| judge | 法官 | `deepseek-reasoner` | `qwen-max` | 需要最强的法律推理和中立性 |

> **选型理由**: DeepSeek 在专业领域推理和逻辑能力上表现最强（尤其是 R1 系列的深度思考链）；Qwen Max 综合能力均衡、长文本处理强。双方使用不同模型还能避免"近亲思维"，产生更真实的对抗效果。
>
> 原被告**刻意使用不同提供商的模型**，这样它们的推理偏向和知识覆盖会有差异，对抗效果更接近真实法庭。

## 快速开始

### 前置条件

- Node.js 22+
- OpenClaw (latest): `npm install -g openclaw@latest`
- Python 3.10+
- API Keys: DeepSeek + 阿里云百炼（Qwen）

### 一键部署

```bash
git clone https://github.com/your-org/moot-court-ai.git
cd moot-court-ai

# 1. 安装依赖
pip install -r requirements.txt

# 2. 配置 API Keys
cp .env.example .env
# 编辑 .env 填入你的 API Keys

# 3. 初始化 OpenClaw 目录结构
chmod +x scripts/setup.sh scripts/setup-auth.sh scripts/init-case.sh scripts/run-trial.sh
./scripts/setup.sh

# 4. 生成 4 个 agent 的 auth-profiles.json
./scripts/setup-auth.sh

# 5. 分发测试案件材料到各 agent workspace
./scripts/init-case.sh cases/sample_case/

# 6. 直接运行庭审工作流（命令行模式）
./scripts/run-trial.sh sample-case

# 7. 查看结果
# output/sample-case-judgment-*.md
```

如需 WebChat 交互模式，再单独启动：

```bash
openclaw gateway --port 18789
# 浏览器访问 http://localhost:18789
```

### Docker 部署（推荐生产环境）

```bash
docker compose up -d
# 访问 http://localhost:18789
```

## 项目结构

```
moot-court-ai/
├── README.md                          # 你正在读的文件
├── LICENSE
├── .env.example                       # API Keys 模板
├── docker-compose.yml                 # Docker 部署
├── requirements.txt                   # Python 依赖
├── openclaw.json                      # OpenClaw 主配置
│
├── agents/                            # Agent 配置（物理隔离）
│   ├── clerk/
│   │   ├── agent/
│   │   │   └── auth-profiles.json
│   │   └── workspace/
│   │       └── SOUL.md
│   ├── plaintiff/
│   │   ├── agent/
│   │   │   └── auth-profiles.json
│   │   └── workspace/                 # ⛔ 被告不可见
│   │       ├── SOUL.md
│   │       ├── complaint.md           # (案件初始化时填入)
│   │       └── evidence/
│   ├── defendant/
│   │   ├── agent/
│   │   │   └── auth-profiles.json
│   │   └── workspace/                 # ⛔ 原告不可见
│   │       ├── SOUL.md
│   │       ├── defense.md
│   │       └── evidence/
│   └── judge/
│       ├── agent/
│       │   └── auth-profiles.json
│       └── workspace/
│           ├── SOUL.md
│           └── templates/
│               ├── judgment-template.md
│               └── risk-report-template.md
│
├── workflows/                         # Lobster 工作流
│   ├── moot-court.lobster             # 主庭审流程
│   └── evidence-round.lobster         # 举证质证子流程（可循环）
│
├── scripts/                           # 部署与运维脚本
│   ├── setup.sh                       # 一键初始化
│   ├── setup-auth.sh                  # API Key 分发
│   ├── init-case.sh                   # 案件材料初始化
│   ├── run-trial.sh                   # 命令行启动庭审并导出判决书
│   └── ingest-law.py                  # 法律知识库入库
│
├── laws/                              # 法律知识库源文件
│   └── README.md                      # 法律数据准备指南
│
├── cases/                             # 标准案件输入（推荐）
│   └── sample_case/                   # 民间借贷纠纷样例
│       ├── case-brief.md
│       ├── complaint.md
│       ├── defense.md
│       ├── plaintiff-evidence/
│       └── defendant-evidence/
│
├── test-cases/                        # 测试案件
│   └── contract-dispute/              # 借款合同纠纷
│       ├── case-brief.md
│       ├── complaint.md
│       ├── defense.md
│       ├── plaintiff-evidence/
│       └── defendant-evidence/
│
└── docs/                              # 文档
    ├── architecture.md                # 架构设计文档
    ├── deployment-guide.md            # 部署指南
    └── user-guide.md                  # 律所操作手册
```

## 技术架构

```
律所内网浏览器 (http://localhost:18789)
       │
       ▼
┌─────────────────────────────────┐
│   OpenClaw Gateway (:18789)     │
│   WebChat Dashboard             │
└──────────────┬──────────────────┘
               │
        Lobster 工作流引擎
        (确定性编排，不让 LLM 决定流程)
               │
    ┌──────────┼──────────┐
    │          │          │
 clerk    plaintiff   defendant    judge
(DeepSeek) (DeepSeek-R1) (Qwen-Max) (DeepSeek-R1)
    │          │          │          │
    │     workspace   workspace  workspace
    │     (私有证据)  (私有证据)  (法律RAG)
    │          │          │          │
    └──────────┴──────────┴──────────┘
               │
         LanceDB 向量库
         (民法典/民诉法/指导案例)
```

> **核心设计**: 用 Lobster 工作流引擎做确定性编排，LLM 只在每个 step 内做"创造性工作"（法律论述），**绝不让 LLM 自己决定流程流转**。

## 庭审流程

| 阶段 | 步骤 | Agent | 说明 |
|------|------|-------|------|
| Phase 1 | 宣布开庭 | 书记员 | 法庭纪律、核对当事人 |
| | 起诉陈述 | 原告 | 宣读诉讼请求、事实与理由 |
| | 答辩 | 被告 | 逐一回应，提出程序性抗辩 |
| Phase 2 | 举证质证 | 原告⇄被告 | 红蓝对抗高潮：三性质证、循环 N 轮 |
| Phase 3 | 归纳焦点 | 法官 | **庭审灵魂步骤**：提炼争议焦点 |
| | 辩论 | 原告→被告 | 围绕焦点的逻辑博弈 |
| Phase 4 | 最后陈述 | 原告→被告 | 总结性发言 |
| | 宣判 | 法官 | 输出判决书 + 风险推演报告 |

## 使用方法（推荐）

### 1) 准备案件材料

将案件按以下结构放在 `cases/<你的案件名>/`：

```text
cases/<your-case>/
├── case-brief.md
├── complaint.md
├── defense.md
├── plaintiff-evidence/
└── defendant-evidence/
```

### 2) 初始化并运行

```bash
./scripts/init-case.sh cases/sample_case/
./scripts/run-trial.sh sample-case
```

### 3) 查看输出

- 判决书：`output/*-judgment-*.md`
- 原始日志：`output/*-raw-*.log`

## 已知限制

- Lobster sub-workflow loop 功能依赖 [openclaw/lobster PR #20](https://github.com/openclaw/lobster/pull/20)，如未合并需手动应用
- LanceDB 向量维度必须与 embedding 模型匹配（参见 `scripts/ingest-law.py` 中的说明）
- 单次庭审约消耗 50K-100K tokens，成本约 ¥2-5（按 DeepSeek 定价）

## 参与贡献

欢迎 PR！特别需要：
- 更多测试案件（不同案由）
- 法律知识库数据（公开的法规/案例）
- 法官 SOUL.md 的法律专业度优化

## License

MIT
