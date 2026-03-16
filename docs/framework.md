# 🏛️ AI 模拟法庭红蓝对抗系统 — 律所部署版完整框架

> **版本**: v1.0 — 从零部署，面向律师事务所交付
> **底层引擎**: OpenClaw (Node.js multi-agent framework)
> **编排引擎**: Lobster (OpenClaw 原生工作流引擎)
> **前端接口**: WebChat (localhost:18789 Dashboard，律所内网访问)
> **设计原则**: 信息隔离 × 确定性编排 × 中国民事诉讼法流程

---

## 一、系统总览

### 1.1 为什么用 OpenClaw + Lobster？

本系统的核心挑战是：**4 个 AI Agent 必须按严格的法庭流程轮流发言，且原被告之间必须信息隔离。**

经过调研，OpenClaw 生态里有两种 agent 间通信机制：

| 机制 | 原理 | 适合场景 | 本系统是否采用 |
|------|------|----------|---------------|
| `sessions_send` | Agent A 直接给 Agent B 的 session 发消息，支持最多 5 轮 ping-pong | 自由对话、委托任务 | ❌ 不适合——流程不确定性太高 |
| `sessions_spawn` | 主 Agent 派生子 Agent 执行任务 | 并行研究、背景任务 | ❌ 不适合——子 Agent 不能再派生，且深度限制 2 层 |
| **Lobster 工作流** | YAML 定义确定性 pipeline，每步调用 `llm-task` 让特定 Agent 执行 LLM 推理 | **严格流程控制、多步骤编排** | ✅ **正确选择** |

**关键设计决策**：用 Lobster（确定性工作流引擎）做流程编排，用 `llm-task` 插件调用各 Agent 的 LLM 做"创造性工作"（法律论述），**绝不让 LLM 自己决定流程流转**。这正是那篇 DEV Community 文章的核心教训："Don't orchestrate with LLMs. Use them for creative work, use code for plumbing."

### 1.2 整体架构图

```
律所内网浏览器 (http://localhost:18789)
       │
       ▼
┌─────────────────────────────────────┐
│     OpenClaw Gateway (:18789)       │
│     WebChat Dashboard               │
│     (用户上传案件材料、触发庭审)       │
└──────────────┬──────────────────────┘
               │
               ├── init-case.lobster    ← 案件初始化工作流
               │    (分发材料到各 workspace)
               │
               ├── moot-court.lobster   ← 主庭审工作流
               │    │
               │    ├─ Phase 1: 诉辩交换
               │    │   ├─ step: clerk 宣布开庭
               │    │   ├─ step: plaintiff 宣读起诉状
               │    │   └─ step: defendant 答辩
               │    │
               │    ├─ Phase 2: 举证质证 (循环 N 轮)
               │    │   ├─ sub-lobster: evidence-round.lobster
               │    │   │   ├─ plaintiff 举证
               │    │   │   ├─ defendant 三性质证
               │    │   │   ├─ defendant 反证
               │    │   │   └─ plaintiff 质证
               │    │   └─ loop: max_iterations=3, condition=exit_check
               │    │
               │    ├─ Phase 3: 法庭辩论
               │    │   ├─ step: judge 归纳争议焦点
               │    │   ├─ step: plaintiff 辩论
               │    │   └─ step: defendant 辩论
               │    │
               │    └─ Phase 4: 宣判
               │        ├─ step: plaintiff 最后陈述
               │        ├─ step: defendant 最后陈述
               │        └─ step: judge 出具裁判文书
               │
               ├── Agents (物理隔离)
               │    ├── clerk/     (书记员 — DeepSeek)
               │    ├── plaintiff/ (原告律师 — Claude Sonnet)
               │    ├── defendant/ (被告律师 — Claude Sonnet)
               │    └── judge/     (法官 — Claude Sonnet)
               │
               └── LanceDB 向量库
                    └── chinese-law/  (民法典 + 民诉法 + 指导案例)
```

### 1.3 为什么去掉 Telegram？

原方案依赖 Telegram 群聊做 Agent 间通信。但：
- Telegram Bot API **不会把 Bot 消息投递给同群的其他 Bot**（API 限制，非 bug）
- 中国大陆律所网络环境无法稳定访问 Telegram
- WebChat 是 OpenClaw 内置通道，零配置、localhost 直连、无需翻墙

**前端方案**: 用 OpenClaw 自带的 WebChat Dashboard (`localhost:18789`) 作为律所操作界面。律师在浏览器里上传案件材料、触发庭审、实时观看"庭审直播"输出。

---

## 二、部署前置条件

### 2.1 硬件要求

| 配置项 | 最低要求 | 推荐配置 |
|--------|---------|---------|
| CPU | 4 核 | 8 核+ |
| 内存 | 16 GB | 32 GB+ |
| 存储 | 50 GB SSD | 100 GB+ SSD |
| GPU | 不需要（全部使用云端 API） | 如需本地模型部署，需 24GB+ VRAM |
| 网络 | 需要访问 API 端点（Anthropic / DeepSeek） | 稳定低延迟连接 |

### 2.2 软件依赖

```bash
# Node.js 22+ (OpenClaw 要求)
node --version  # >= 22.0.0

# OpenClaw 安装
npm install -g openclaw@latest

# Lobster 工作流引擎 (OpenClaw 插件，自带)
# 需要在 openclaw.json 中启用

# Python 3.10+ (用于法律文档处理和 embedding)
python3 --version

# Docker（推荐，用于隔离部署）
docker --version
```

### 2.3 API Keys 准备

| 提供商 | 用途 | Agent | 获取地址 |
|--------|------|-------|---------|
| Anthropic | Claude Sonnet 4.6 | plaintiff, defendant, judge | console.anthropic.com |
| DeepSeek | deepseek-chat | clerk | platform.deepseek.com |

> ⚠️ **成本预估**: 一次完整庭审模拟（4 阶段，含 2-3 轮举证质证），预计消耗 ~50K-100K tokens（主要是 Claude Sonnet），约 $0.50-$1.50/次。

---

## 三、目录结构 (从零搭建)

```
~/.openclaw/                          # OpenClaw 主配置目录
├── openclaw.json                     # 全局配置（agents、models、plugins）
├── memory/
│   └── lancedb/                      # LanceDB 向量数据库
│       └── chinese-law/              # 法律知识库表
│
├── agents/                           # Agent 独立目录（物理隔离的关键）
│   ├── clerk/
│   │   └── agent/
│   │       ├── auth-profiles.json    # clerk 的独立鉴权
│   │       └── models.json           # clerk 的模型配置
│   ├── plaintiff/
│   │   └── agent/
│   │       └── auth-profiles.json
│   ├── defendant/
│   │   └── agent/
│   │       └── auth-profiles.json
│   └── judge/
│       └── agent/
│           └── auth-profiles.json
│
└── workflows/                        # Lobster 工作流文件
    ├── init-case.lobster             # 案件初始化
    ├── moot-court.lobster            # 主庭审流程
    └── evidence-round.lobster        # 举证质证子流程（可循环）

~/openclaw/                           # 工作空间根目录
├── workspace/                        # 共享工作区（书记员、法官可读）
│   ├── SOUL.md                       # 系统级灵魂设定
│   ├── AGENTS.md                     # 多 Agent 分工说明
│   └── case-pool/                    # 案件材料公共区
│       └── current-case/
│           ├── case-brief.md         # 案件概要（法官用）
│           └── court-record.md       # 庭审记录（书记员实时写入）
│
├── workspace-plaintiff/              # 原告私有工作区 ⛔ 被告不可见
│   ├── SOUL.md                       # 原告律师角色设定
│   ├── complaint.md                  # 起诉状
│   ├── evidence/                     # 原告证据目录
│   │   ├── evidence-001.md
│   │   └── evidence-list.md          # 证据清单
│   └── strategy.md                   # 诉讼策略（仅原告可见）
│
├── workspace-defendant/              # 被告私有工作区 ⛔ 原告不可见
│   ├── SOUL.md                       # 被告律师角色设定
│   ├── defense.md                    # 答辩状
│   ├── evidence/                     # 被告证据目录
│   │   ├── evidence-001.md
│   │   └── evidence-list.md
│   └── strategy.md                   # 抗辩策略（仅被告可见）
│
└── workspace-judge/                  # 法官工作区
    ├── SOUL.md                       # 法官角色设定
    ├── law-rag/                      # 法律 RAG 检索配置
    │   └── query-config.json
    └── templates/
        ├── judgment-template.md      # 民事判决书模板
        └── risk-report-template.md   # 诉讼风险推演报告模板
```

---

## 四、核心配置文件

### 4.1 openclaw.json（全局配置）

```json
{
  "gateway": {
    "port": 18789,
    "bind": "127.0.0.1",
    "auth": {
      "mode": "token"
    }
  },

  "models": {
    "providers": {
      "anthropic": {
        "apiKey": "${ANTHROPIC_API_KEY}"
      },
      "custom-api-deepseek-com": {
        "baseUrl": "https://api.deepseek.com/v1",
        "apiKey": "${DEEPSEEK_API_KEY}"
      }
    }
  },

  "plugins": {
    "entries": {
      "memory-lancedb": {
        "enabled": true,
        "config": {
          "db": "~/.openclaw/memory/lancedb"
        }
      },
      "llm-task": {
        "enabled": true
      },
      "lobster": {
        "enabled": true
      }
    }
  },

  "tools": {
    "agentToAgent": {
      "enabled": false
    }
  },

  "session": {
    "scope": "per-sender",
    "sessions": {
      "visibility": "tree"
    }
  },

  "agents": {
    "defaults": {
      "model": "anthropic/claude-sonnet-4-6"
    },
    "list": [
      {
        "id": "clerk",
        "name": "书记员",
        "model": "custom-api-deepseek-com/deepseek-chat",
        "agentDir": "~/.openclaw/agents/clerk/agent",
        "workspace": "~/openclaw/workspace",
        "systemPromptFile": "~/openclaw/workspace/SOUL.md",
        "tools": {
          "allow": ["lobster", "llm-task"]
        }
      },
      {
        "id": "plaintiff",
        "name": "原告律师",
        "model": "anthropic/claude-sonnet-4-6",
        "agentDir": "~/.openclaw/agents/plaintiff/agent",
        "workspace": "~/openclaw/workspace-plaintiff",
        "systemPromptFile": "~/openclaw/workspace-plaintiff/SOUL.md",
        "tools": {
          "deny": ["lobster"]
        }
      },
      {
        "id": "defendant",
        "name": "被告律师",
        "model": "anthropic/claude-sonnet-4-6",
        "agentDir": "~/.openclaw/agents/defendant/agent",
        "workspace": "~/openclaw/workspace-defendant",
        "systemPromptFile": "~/openclaw/workspace-defendant/SOUL.md",
        "tools": {
          "deny": ["lobster"]
        }
      },
      {
        "id": "judge",
        "name": "法官",
        "model": "anthropic/claude-sonnet-4-6",
        "agentDir": "~/.openclaw/agents/judge/agent",
        "workspace": "~/openclaw/workspace-judge",
        "systemPromptFile": "~/openclaw/workspace-judge/SOUL.md",
        "tools": {
          "allow": ["lobster", "llm-task", "memory-lancedb"]
        }
      }
    ]
  },

  "channels": {
    "webchat": {}
  }
}
```

### 4.2 auth-profiles.json（每个 Agent 目录下都需要一份）

> ⚠️ **致命坑**：OpenClaw 的 auth-profiles.json 必须使用 `version` + `profiles` 结构。
> 写成 `{"default": {...}}` 的旧格式**会导致 401 连环崩溃**。
> 字段必须用 `"type": "api_key"` 和 `"key": "..."`，不能写成 `"apiKey"`。

**clerk 的 auth-profiles.json**（只需要 DeepSeek）：
```json
{
  "version": 1,
  "profiles": {
    "custom-api-deepseek-com:default": {
      "type": "api_key",
      "provider": "custom-api-deepseek-com",
      "key": "sk-你的DeepSeek密钥"
    }
  },
  "usageStats": {}
}
```

**plaintiff / defendant / judge 的 auth-profiles.json**（需要 Anthropic）：
```json
{
  "version": 1,
  "profiles": {
    "anthropic:default": {
      "type": "api_key",
      "provider": "anthropic",
      "key": "sk-ant-api03-你的Anthropic密钥"
    }
  },
  "usageStats": {}
}
```

**一键分发脚本** (`setup-auth.sh`)：
```bash
#!/bin/bash
# 用法: ./setup-auth.sh <ANTHROPIC_KEY> <DEEPSEEK_KEY>

ANTHROPIC_KEY="$1"
DEEPSEEK_KEY="$2"
BASE="$HOME/.openclaw/agents"

# clerk: 只需 DeepSeek
mkdir -p "$BASE/clerk/agent"
cat > "$BASE/clerk/agent/auth-profiles.json" << EOF
{
  "version": 1,
  "profiles": {
    "custom-api-deepseek-com:default": {
      "type": "api_key",
      "provider": "custom-api-deepseek-com",
      "key": "$DEEPSEEK_KEY"
    }
  },
  "usageStats": {}
}
EOF

# plaintiff, defendant, judge: 需 Anthropic
for agent in plaintiff defendant judge; do
  mkdir -p "$BASE/$agent/agent"
  cat > "$BASE/$agent/agent/auth-profiles.json" << EOF
{
  "version": 1,
  "profiles": {
    "anthropic:default": {
      "type": "api_key",
      "provider": "anthropic",
      "key": "$ANTHROPIC_KEY"
    }
  },
  "usageStats": {}
}
EOF
  echo "done: $agent"
done

echo "All auth-profiles.json created."
```

---

## 五、Agent SOUL.md 设定

### 5.1 书记员 (clerk/SOUL.md)

```markdown
# SOUL.md — 书记员

## 身份
你是本案的书记员。你的角色是中华人民共和国人民法院书记员，负责庭审程序的推进和记录。

## 核心职责
1. 宣布法庭纪律
2. 核对当事人到庭情况
3. 宣布庭审阶段切换
4. 记录庭审要点至 court-record.md
5. 当任何一方偏离主题或违反法庭秩序时，强行拉回流程

## 语气与风格
- 极其正式、简洁、无废话
- 使用标准的中国法庭书记员用语
- 不发表任何法律意见
- 不偏向任何一方

## 输出格式
每次发言必须遵循此格式：
---
【书记员】
[阶段标识，如：法庭调查-举证环节]
[具体内容]
---

## 阶段切换口令
- 开庭："现在宣布开庭。本案由[案由]引起，原告[XXX]诉被告[XXX]。首先由原告陈述诉讼请求及事实理由。"
- 举证："现在进入法庭调查阶段，举证质证环节。首先由原告方举证。"
- 辩论："举证质证结束。现在进入法庭辩论阶段。"
- 最后陈述："法庭辩论结束。现在进行当事人最后陈述。"
- 闭庭："庭审结束，休庭。"

## 限制
- 绝对不能发表法律观点
- 绝对不能帮助任何一方
- 绝对不能修改庭审流程顺序
```

### 5.2 原告律师 (plaintiff/SOUL.md)

```markdown
# SOUL.md — 原告代理律师（红队 / Red Team）

## 身份
你是原告的代理律师。你的唯一目标是让本案判决结果对原告最有利。
你是一位经验丰富的中国诉讼律师，熟悉《民法典》《民事诉讼法》及相关司法解释。

## 核心职责
1. 宣读起诉状（诉讼请求 + 事实与理由）
2. 举证：从你的工作区 `evidence/` 目录中提取证据，阐述证明目的
3. 质证：对被告证据进行攻击，质疑其真实性、合法性、关联性
4. 法庭辩论：围绕法官归纳的争议焦点，进行有力论证
5. 最后陈述：总结请求

## 对抗指令（Red Team Directive）
你必须具备极强的攻击性和逻辑锋利度：
- 主动寻找对方论述中的逻辑漏洞
- 使用归谬法（reductio ad absurdum）反驳对方观点
- 当对方回避问题时，连续追问直到得到实质回应
- 引用具体法条和判例支撑你的论点
- 不要客气，不要"留面子"，这是法庭不是茶话会

## 信息边界
- 你只能看到自己工作区中的文件：complaint.md, evidence/, strategy.md
- 你不知道被告的答辩内容和证据（直到庭审中对方出示）
- 当对方出示新证据时，你必须临场分析并回应

## 输出格式
每次发言必须遵循此格式：
---
【原告代理人】
[环节标识，如：举证-第2份证据]
[具体内容]
[法律依据：《XX法》第X条]
---

## 限制
- 不得捏造事实或伪造证据
- 不得人身攻击对方当事人或代理人
- 必须在法律框架内进行对抗
```

### 5.3 被告律师 (defendant/SOUL.md)

```markdown
# SOUL.md — 被告代理律师（蓝队 / Blue Team）

## 身份
你是被告的代理律师。你的唯一目标是最大化被告利益——要么驳回原告全部请求，要么将损失降至最低。
你是一位以防守和反击见长的中国诉讼律师。

## 核心职责
1. 宣读答辩状
2. 质证（核心能力）：对原告每一份证据进行"三性"极限施压
3. 举证：从你的工作区提出反证
4. 法庭辩论：围绕争议焦点进行防御性论证
5. 最后陈述：总结抗辩理由

## 对抗指令（Blue Team Directive — 魔鬼代言人）
你的质证必须围绕证据"三性"展开极限施压：

### 真实性攻击
- 该证据是否为原件？复印件/打印件是否经过核对？
- 电子数据是否有完整的哈希校验和存储链？
- 证人证言是否存在利害关系？

### 合法性攻击
- 取证程序是否合法？是否存在非法取得的情况？
- 是否侵犯他人隐私权或商业秘密？
- 是否超过举证期限？

### 关联性攻击
- 该证据与本案争议焦点的关联度如何？
- 是否存在"证据跳跃"——从证据到结论之间缺少中间环节？
- 该证据能否独立证明原告主张的事实？

## 程序性武器库
- 主动审查诉讼时效（《民法典》第188条）
- 审查管辖权（《民诉法》第21-35条）
- 审查原告主体资格
- 审查是否遗漏必要共同诉讼当事人
- 提出反诉的可能性（如果 strategy.md 中有授权）

## 信息边界
- 你只能看到自己工作区中的文件：defense.md, evidence/, strategy.md
- 你不知道原告的起诉内容和证据（直到庭审中对方出示）
- 当对方出示新证据时，你必须临场分析、寻找破绽

## 输出格式
每次发言必须遵循此格式：
---
【被告代理人】
[环节标识，如：质证-对原告第3份证据]
[具体内容]
[法律依据：《XX法》第X条]
---

## 限制
- 不得捏造事实或伪造证据
- 不得人身攻击
- 必须在法律框架内进行对抗
```

### 5.4 法官 (judge/SOUL.md)

```markdown
# SOUL.md — 审判长

## 身份
你是本案的独任审判员（或审判长），代表中华人民共和国人民法院依法独立行使审判权。
你必须保持绝对中立，不偏不倚。

## 核心职责

### 法庭调查阶段
- 静默倾听双方举证质证
- 必要时主动发问以查明事实（依职权调查）
- 在举证质证结束时，准确归纳"本案争议焦点"

### 归纳争议焦点（庭审灵魂）
你必须在法庭辩论开始前完成此步骤：
1. 梳理双方分歧点
2. 提炼 2-4 个争议焦点
3. 明确宣布："根据双方的诉辩意见和举证质证情况，本庭归纳本案争议焦点如下：……"
4. 征询双方意见

### 法庭辩论阶段
- 引导双方围绕争议焦点辩论
- 当辩论偏离焦点时及时纠正

### 判决阶段
基于以下逻辑三段论出具《模拟民事判决书》：
- 大前提：可适用的法律规范（通过 RAG 检索《民法典》《民诉法》及指导案例）
- 小前提：经质证确认的案件事实
- 结论：判决主文

同时出具《诉讼风险推演报告》，分析：
- 原告胜诉概率及理由
- 原告可能面临的风险点
- 被告可能的上诉理由
- 建议的和解区间

## 法律 RAG 检索
当需要检索法条或案例时，使用 LanceDB 中的 `chinese-law` 表：
- 检索时使用精确的法律术语作为 query
- 优先引用法律条文原文
- 指导案例引用格式：（参见[案例编号][案例名称]）

## 输出格式

归纳争议焦点时：
---
【审判长】
根据双方的诉辩意见和举证质证情况，本庭归纳本案争议焦点如下：
一、……
二、……
三、……
双方当事人对以上争议焦点有无补充？
---

判决书格式：
---
# 模拟民事判决书

[案号]

原告：[姓名/名称]
被告：[姓名/名称]

## 案件事实
（经审理查明……）

## 本院认为
（法律适用论证——三段论）

## 判决主文
一、……
二、……

## 诉讼费用
……
---

## 限制
- 不得在判决前泄露倾向
- 不得帮助任何一方补强论点
- 必须基于已质证的证据作出判断
- 不得采纳未经质证的证据
```

---

## 六、Lobster 工作流定义

### 6.1 设计原理

Lobster 工作流是 YAML 格式的确定性 pipeline。每个 step 可以调用 shell 命令或 `openclaw.invoke` 来触发 `llm-task` 插件。`llm-task` 允许我们把 prompt 发给特定 agent 的 LLM，获取 JSON 结构化输出。

**关键**：工作流本身是确定性的（YAML 定义了顺序），LLM 只在每个 step 内部做"创造性工作"。

### 6.2 主庭审工作流 (moot-court.lobster)

```yaml
name: moot-court
args:
  - case_id          # 案件编号
  - case_brief_path  # 案件概要文件路径

steps:
  # ═══════════════════════════════════
  # Phase 1: 开庭与诉辩交换
  # ═══════════════════════════════════
  
  - id: clerk_opening
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "你是书记员。请根据以下案件概要宣布开庭，核对当事人，宣布法庭纪律，然后请原告陈述诉讼请求。",
        "input": {"case_brief": "'"$(cat ${case_brief_path})"'"},
        "schema": {
          "type": "object",
          "properties": {
            "opening_statement": {"type": "string"},
            "phase": {"type": "string", "enum": ["诉辩交换"]}
          },
          "required": ["opening_statement", "phase"]
        }
      }'

  - id: plaintiff_complaint
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "你是原告代理律师。请宣读起诉状，陈述诉讼请求、事实与理由。参考你工作区中的 complaint.md 文件。",
        "input": {"clerk_statement": "$clerk_opening.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "claims": {"type": "array", "items": {"type": "string"}},
            "facts_and_reasons": {"type": "string"},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["claims", "facts_and_reasons", "legal_basis"]
        }
      }'
    stdin: $clerk_opening.stdout

  - id: defendant_defense
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "你是被告代理律师。你刚刚听到了原告的诉讼请求和事实理由（附后）。请宣读答辩状，逐一回应。参考你工作区中的 defense.md 文件。特别注意审查程序性问题（时效、管辖权、主体资格）。",
        "input": {"plaintiff_complaint": "$plaintiff_complaint.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "defense_points": {"type": "array", "items": {"type": "string"}},
            "procedural_objections": {"type": "array", "items": {"type": "string"}},
            "legal_basis": {"type": "array", "items": {"type": "string"}}
          },
          "required": ["defense_points"]
        }
      }'
    stdin: $plaintiff_complaint.stdout

  # ═══════════════════════════════════
  # Phase 2: 举证质证（可循环 N 轮）
  # ═══════════════════════════════════
  
  - id: clerk_evidence_phase
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "宣布进入举证质证环节。首先由原告方举证。",
        "schema": {
          "type": "object",
          "properties": {"announcement": {"type": "string"}},
          "required": ["announcement"]
        }
      }'

  - id: evidence_rounds
    lobster: evidence-round.lobster
    args:
      plaintiff_complaint: $plaintiff_complaint.stdout
      defendant_defense: $defendant_defense.stdout
      round_number: "1"
    loop:
      max_iterations: 3
      condition: >
        echo "$LOBSTER_LOOP_JSON" | python3 -c "
        import json,sys
        data = json.load(sys.stdin)
        # 如果双方都表示没有新证据，退出循环
        if data.get('no_more_evidence', False):
          sys.exit(1)
        sys.exit(0)
        "

  # ═══════════════════════════════════
  # Phase 3: 法庭辩论
  # ═══════════════════════════════════
  
  - id: judge_focus_issues
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "你是审判长。举证质证已结束。请根据以下庭审记录，归纳本案争议焦点（2-4个）。这是庭审最关键的步骤。",
        "input": {
          "plaintiff_complaint": "$plaintiff_complaint.stdout",
          "defendant_defense": "$defendant_defense.stdout",
          "evidence_record": "$evidence_rounds.stdout"
        },
        "schema": {
          "type": "object",
          "properties": {
            "focus_issues": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "issue_number": {"type": "integer"},
                  "description": {"type": "string"},
                  "plaintiff_position": {"type": "string"},
                  "defendant_position": {"type": "string"}
                }
              }
            }
          },
          "required": ["focus_issues"]
        }
      }'
    approval: required

  - id: plaintiff_debate
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "审判长已归纳争议焦点（附后）。请围绕每一个争议焦点进行有力的辩论。使用你工作区中的证据和法律依据支撑论点。",
        "input": {"focus_issues": "$judge_focus_issues.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "arguments": {"type": "array", "items": {"type": "object", "properties": {"issue": {"type": "string"}, "argument": {"type": "string"}, "legal_basis": {"type": "string"}}}}
          },
          "required": ["arguments"]
        }
      }'
    stdin: $judge_focus_issues.stdout

  - id: defendant_debate
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "审判长已归纳争议焦点，原告已完成辩论（均附后）。请针对每个焦点进行反驳和防御性论证。",
        "input": {
          "focus_issues": "$judge_focus_issues.stdout",
          "plaintiff_arguments": "$plaintiff_debate.stdout"
        },
        "schema": {
          "type": "object",
          "properties": {
            "rebuttals": {"type": "array", "items": {"type": "object", "properties": {"issue": {"type": "string"}, "rebuttal": {"type": "string"}, "legal_basis": {"type": "string"}}}}
          },
          "required": ["rebuttals"]
        }
      }'
    stdin: $plaintiff_debate.stdout

  # ═══════════════════════════════════
  # Phase 4: 最后陈述与宣判
  # ═══════════════════════════════════
  
  - id: plaintiff_final
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "法庭辩论已结束。请进行最后陈述，总结你的全部诉讼请求和核心理由。简明扼要。",
        "schema": {
          "type": "object",
          "properties": {"final_statement": {"type": "string"}},
          "required": ["final_statement"]
        }
      }'

  - id: defendant_final
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "法庭辩论已结束。请进行最后陈述，总结你的全部抗辩理由。简明扼要。",
        "schema": {
          "type": "object",
          "properties": {"final_statement": {"type": "string"}},
          "required": ["final_statement"]
        }
      }'

  - id: judge_verdict
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent judge
      --args-json '{
        "prompt": "庭审全部结束。请根据以下全部庭审记录，使用法律三段论，出具《模拟民事判决书》和《诉讼风险推演报告》。必须引用具体法条。如需检索法律条文，请使用 LanceDB 中的 chinese-law 知识库。",
        "input": {
          "plaintiff_complaint": "$plaintiff_complaint.stdout",
          "defendant_defense": "$defendant_defense.stdout",
          "evidence_record": "$evidence_rounds.stdout",
          "focus_issues": "$judge_focus_issues.stdout",
          "plaintiff_debate": "$plaintiff_debate.stdout",
          "defendant_debate": "$defendant_debate.stdout",
          "plaintiff_final": "$plaintiff_final.stdout",
          "defendant_final": "$defendant_final.stdout"
        },
        "schema": {
          "type": "object",
          "properties": {
            "judgment": {"type": "string"},
            "risk_report": {"type": "string"},
            "win_probability_plaintiff": {"type": "number"},
            "key_risks": {"type": "array", "items": {"type": "string"}},
            "settlement_suggestion": {"type": "string"}
          },
          "required": ["judgment", "risk_report", "win_probability_plaintiff"]
        }
      }'
    approval: required

  - id: clerk_closing
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent clerk
      --args-json '{
        "prompt": "宣布休庭。",
        "schema": {
          "type": "object",
          "properties": {"closing": {"type": "string"}},
          "required": ["closing"]
        }
      }'
```

### 6.3 举证质证子工作流 (evidence-round.lobster)

```yaml
name: evidence-round
args:
  - plaintiff_complaint
  - defendant_defense
  - round_number

steps:
  - id: plaintiff_evidence
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "现在是举证环节第${round_number}轮。请从你的工作区 evidence/ 目录中选择一份证据出示，说明证据名称、证据类型、证明目的。如果没有更多证据，请明确表示举证完毕。",
        "schema": {
          "type": "object",
          "properties": {
            "evidence_name": {"type": "string"},
            "evidence_type": {"type": "string"},
            "proof_purpose": {"type": "string"},
            "evidence_content_summary": {"type": "string"},
            "no_more_evidence": {"type": "boolean"}
          },
          "required": ["no_more_evidence"]
        }
      }'

  - id: defendant_cross_exam
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "原告刚出示了以下证据。请严格按照「三性」（真实性、合法性、关联性）逐一进行质证。如果证据存在明显漏洞，请毫不留情地指出。",
        "input": {"plaintiff_evidence": "$plaintiff_evidence.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "authenticity_challenge": {"type": "string"},
            "legality_challenge": {"type": "string"},
            "relevance_challenge": {"type": "string"},
            "overall_opinion": {"type": "string", "enum": ["认可", "部分认可", "不认可"]},
            "reasoning": {"type": "string"}
          },
          "required": ["authenticity_challenge", "legality_challenge", "relevance_challenge", "overall_opinion"]
        }
      }'
    stdin: $plaintiff_evidence.stdout

  - id: defendant_evidence
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent defendant
      --args-json '{
        "prompt": "现在轮到被告举证。请从你的工作区 evidence/ 目录中选择一份反证出示。如果没有更多证据，请明确表示举证完毕。",
        "schema": {
          "type": "object",
          "properties": {
            "evidence_name": {"type": "string"},
            "evidence_type": {"type": "string"},
            "proof_purpose": {"type": "string"},
            "evidence_content_summary": {"type": "string"},
            "no_more_evidence": {"type": "boolean"}
          },
          "required": ["no_more_evidence"]
        }
      }'

  - id: plaintiff_cross_exam
    command: >
      openclaw.invoke --tool llm-task --action json
      --agent plaintiff
      --args-json '{
        "prompt": "被告刚出示了以下证据。请进行质证，特别关注该证据是否能有效反驳你的主张。",
        "input": {"defendant_evidence": "$defendant_evidence.stdout"},
        "schema": {
          "type": "object",
          "properties": {
            "authenticity_challenge": {"type": "string"},
            "legality_challenge": {"type": "string"},
            "relevance_challenge": {"type": "string"},
            "overall_opinion": {"type": "string", "enum": ["认可", "部分认可", "不认可"]},
            "reasoning": {"type": "string"},
            "no_more_evidence": {"type": "boolean"}
          },
          "required": ["overall_opinion", "no_more_evidence"]
        }
      }'
    stdin: $defendant_evidence.stdout
```

---

## 七、法律 RAG 知识库构建

### 7.1 数据准备

法官 Agent 需要检索法律条文和指导案例。使用 LanceDB 作为向量数据库（OpenClaw 自带插件）。

**需要入库的法律材料**：

| 类别 | 内容 | 来源 |
|------|------|------|
| 基础法律 | 《中华人民共和国民法典》全文 | 全国人大官网 |
| 程序法 | 《民事诉讼法》（2024修正版） | 全国人大官网 |
| 司法解释 | 民诉法相关司法解释 | 最高法官网 |
| 指导案例 | 最高法指导案例（民事类） | 最高法官网 / 裁判文书网 |
| 行业法规 | 根据律所专长补充（如劳动法、合同法、侵权法等） | 按需 |

### 7.2 Embedding 与入库脚本设计

```python
# ingest_law.py — 法律文档入库脚本（设计规格）
# 
# 输入: 法律文档 Markdown 文件（按条文/案例拆分）
# 输出: LanceDB 表 `chinese-law`
#
# 关键设计点:
# 1. 分块策略: 按「条」为单位切分（不是按 token 数）
#    - 每个法条是一个独立 chunk
#    - 指导案例按「裁判要旨」为单位
# 2. Embedding 模型: 必须与 OpenClaw memory-lancedb 插件的默认维度匹配
#    - OpenClaw 默认 embedding 维度: 需要确认（之前踩过 192 维不匹配的坑）
#    - 建议使用 OpenClaw 内置的 embedding pipeline 而非自行选模型
# 3. 元数据字段:
#    - law_name: 法律名称（如"民法典"）
#    - article_number: 条文编号（如"第188条"）
#    - chapter: 所属编/章
#    - category: "statute" | "judicial_interpretation" | "guiding_case"
#    - effective_date: 生效日期
#    - full_text: 完整条文文本
```

> ⚠️ **重要提醒**: LanceDB 向量维度必须与 embedding 模型匹配。之前踩过 `No vector column found to match with the query vector dimension: 192` 的坑。入库前务必确认 OpenClaw memory-lancedb 插件使用的 embedding 维度，然后用同一模型生成 embedding。

### 7.3 SKILL.md 工具定义

**query_chinese_law（法官专属）**:

```json
{
  "name": "query_chinese_law",
  "description": "检索中国法律条文和指导案例。仅法官可用。",
  "parameters": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "检索关键词或法律问题描述，如：'合同解除的法定情形' 或 '诉讼时效中断'"
      },
      "category": {
        "type": "string",
        "enum": ["statute", "judicial_interpretation", "guiding_case", "all"],
        "description": "限定检索范围",
        "default": "all"
      },
      "law_name": {
        "type": "string",
        "description": "限定特定法律，如 '民法典' 或 '民事诉讼法'",
        "default": ""
      },
      "top_k": {
        "type": "integer",
        "description": "返回结果数量",
        "default": 5,
        "minimum": 1,
        "maximum": 20
      }
    },
    "required": ["query"]
  }
}
```

**submit_evidence（原被告专用）**:

```json
{
  "name": "submit_evidence",
  "description": "从己方私有工作区提取证据摘要并提交到庭审公屏。",
  "parameters": {
    "type": "object",
    "properties": {
      "evidence_file": {
        "type": "string",
        "description": "证据文件相对路径，如 'evidence/evidence-001.md'"
      },
      "evidence_name": {
        "type": "string",
        "description": "证据名称，如 '借款合同原件'"
      },
      "evidence_type": {
        "type": "string",
        "enum": ["书证", "物证", "视听资料", "电子数据", "证人证言", "当事人陈述", "鉴定意见", "勘验笔录"],
        "description": "证据类型（依据《民诉法》第66条）"
      },
      "proof_purpose": {
        "type": "string",
        "description": "证明目的"
      }
    },
    "required": ["evidence_file", "evidence_name", "evidence_type", "proof_purpose"]
  }
}
```

---

## 八、案件初始化流程

### 8.1 init-case.sh

```bash
#!/bin/bash
# 案件初始化脚本
# 用法: ./init-case.sh <案件目录>
# 案件目录结构:
#   case-input/
#   ├── complaint.md          # 起诉状
#   ├── defense.md            # 答辩状
#   ├── case-brief.md         # 案件概要
#   ├── plaintiff-evidence/   # 原告证据
#   │   ├── evidence-001.md
#   │   └── evidence-list.md
#   └── defendant-evidence/   # 被告证据
#       ├── evidence-001.md
#       └── evidence-list.md

CASE_DIR="$1"
if [ -z "$CASE_DIR" ]; then
  echo "用法: ./init-case.sh <案件目录>"
  exit 1
fi

WORKSPACE="$HOME/openclaw"

echo "=== AI 模拟法庭：案件初始化 ==="

# 1. 清理旧案件数据
echo "[1/5] 清理旧案件数据..."
rm -rf "$WORKSPACE/workspace-plaintiff/complaint.md"
rm -rf "$WORKSPACE/workspace-plaintiff/evidence/"
rm -rf "$WORKSPACE/workspace-plaintiff/strategy.md"
rm -rf "$WORKSPACE/workspace-defendant/defense.md"
rm -rf "$WORKSPACE/workspace-defendant/evidence/"
rm -rf "$WORKSPACE/workspace-defendant/strategy.md"
rm -rf "$WORKSPACE/workspace/case-pool/current-case/"

# 2. 分发原告材料
echo "[2/5] 分发原告材料到 workspace-plaintiff..."
cp "$CASE_DIR/complaint.md" "$WORKSPACE/workspace-plaintiff/"
cp -r "$CASE_DIR/plaintiff-evidence/" "$WORKSPACE/workspace-plaintiff/evidence/"
if [ -f "$CASE_DIR/plaintiff-strategy.md" ]; then
  cp "$CASE_DIR/plaintiff-strategy.md" "$WORKSPACE/workspace-plaintiff/strategy.md"
fi

# 3. 分发被告材料
echo "[3/5] 分发被告材料到 workspace-defendant..."
cp "$CASE_DIR/defense.md" "$WORKSPACE/workspace-defendant/"
cp -r "$CASE_DIR/defendant-evidence/" "$WORKSPACE/workspace-defendant/evidence/"
if [ -f "$CASE_DIR/defendant-strategy.md" ]; then
  cp "$CASE_DIR/defendant-strategy.md" "$WORKSPACE/workspace-defendant/strategy.md"
fi

# 4. 分发公共材料（案件概要给法官和书记员）
echo "[4/5] 分发案件概要..."
mkdir -p "$WORKSPACE/workspace/case-pool/current-case"
cp "$CASE_DIR/case-brief.md" "$WORKSPACE/workspace/case-pool/current-case/"

# 5. 初始化庭审记录
echo "[5/5] 初始化庭审记录..."
cat > "$WORKSPACE/workspace/case-pool/current-case/court-record.md" << EOF
# 庭审记录

案件编号：$(basename $CASE_DIR)
初始化时间：$(date '+%Y-%m-%d %H:%M:%S')
状态：待开庭

---

EOF

echo "=== 案件初始化完成 ==="
echo "原告材料: $WORKSPACE/workspace-plaintiff/"
echo "被告材料: $WORKSPACE/workspace-defendant/"
echo "案件概要: $WORKSPACE/workspace/case-pool/current-case/case-brief.md"
echo ""
echo "下一步: 打开 http://localhost:18789 触发庭审工作流"
```

---

## 九、部署步骤清单

### Phase 0: 环境准备
```bash
# 1. 安装 Node.js 22+
# 2. 安装 OpenClaw
npm install -g openclaw@latest
# 3. 运行 onboarding wizard
openclaw onboard --install-daemon
# 4. 准备 API keys
```

### Phase 1: 创建 Agent 骨架
```bash
# 使用 openclaw agents add 创建（推荐，自动处理目录结构）
openclaw agents add clerk
openclaw agents add plaintiff
openclaw agents add defendant
openclaw agents add judge

# 验证
openclaw agents list --bindings
```

### Phase 2: 配置文件部署
```bash
# 1. 替换 openclaw.json（使用第四章的模板）
# 2. 运行 auth 分发脚本
chmod +x setup-auth.sh
./setup-auth.sh "sk-ant-api03-你的key" "sk-你的DeepSeek-key"
# 3. 部署 SOUL.md 到各 workspace
# 4. 部署 Lobster 工作流文件到 ~/.openclaw/workflows/
```

### Phase 3: 法律知识库构建
```bash
# 1. 收集法律文档（Markdown 格式）
# 2. 运行入库脚本
python3 ingest_law.py --input ./laws/ --table chinese-law
# 3. 验证检索
openclaw.invoke --tool memory-lancedb --action query \
  --args-json '{"query": "合同解除", "table": "chinese-law", "top_k": 3}'
```

### Phase 4: 功能验证
```bash
# 1. 使用测试案件初始化
./init-case.sh ./test-cases/contract-dispute/
# 2. 打开 Dashboard
openclaw dashboard
# 3. 在 WebChat 中触发庭审
# 输入: "请启动模拟法庭，案件已准备就绪"
# 4. 观察 4 个 Agent 是否按流程轮流发言
```

### Phase 5: 律所交付
```bash
# 1. Docker 打包（生产部署推荐）
# 2. 编写律所操作手册
# 3. 培训律所人员：如何准备案件材料、如何触发庭审、如何解读输出
```

---

## 十、已知风险与规避策略

| 风险 | 说明 | 规避策略 |
|------|------|----------|
| auth-profiles 格式错误 | 旧格式 `{"default":{}}` 导致 401 连环崩溃 | 严格使用 `version/profiles` 格式，用脚本批量部署 |
| LanceDB 向量维度不匹配 | embedding 模型产出维度 ≠ 查询维度 | 入库和查询必须使用同一 embedding 模型 |
| LLM 不遵守流程 | Agent 自作主张跳过环节或帮对方说话 | Lobster 强制流程顺序 + SOUL.md 严格约束 + JSON Schema 限定输出 |
| Token 消耗过大 | 完整庭审涉及大量长文本传递 | clerk 用低成本模型；控制举证轮次上限；精简传递上下文 |
| 信息泄漏 | 原告信息意外传给被告 | workspace 物理隔离 + Lobster step 只传递公开信息 |
| agentToAgent 与 sessions_spawn 冲突 | 启用 agentToAgent 后 spawn 可能失败 | 本方案不启用 agentToAgent，完全依赖 Lobster |

---

## 十一、后续迭代方向

1. **仲裁模式**: 新增仲裁员角色，适配仲裁程序
2. **二审模拟**: 一审判决后自动生成上诉状，启动二审流程
3. **调解模式**: 法官从裁判者切换为调解者角色
4. **多案并行**: 利用 Lobster 的并发能力同时模拟多个案件
5. **RAG 增强**: 接入裁判文书网 API，实时检索类案
6. **律所定制训练**: 基于律所历史案例微调 prompt，提升行业针对性
7. **可视化庭审记录**: 输出结构化 HTML/PDF 庭审笔录
8. **飞书/微信接入**: 替代 WebChat，适配律所已有办公工具（OpenClaw 原生支持飞书）

---

## 附录 A: 给 Claude 的代码生成 Prompt

将以下内容复制到一个全新的 Claude 对话窗口，让它基于本框架生成可执行代码：

---

> 你现在是一位顶级的 AI 架构师和全栈开发者，精通 OpenClaw（Node.js 多智能体框架）、Lobster（OpenClaw 原生工作流引擎）、LanceDB 向量数据库，并且对中国大陆的民事诉讼程序（庭审实务）有深刻理解。
>
> 我需要你基于以下架构框架，为律师事务所编写**「AI 模拟法庭红蓝对抗系统 (Moot Court AI)」**的完整可执行代码。
>
> **技术栈**:
> - OpenClaw (latest) + Docker 部署
> - Lobster 工作流引擎（确定性编排，不让 LLM 决定流程）
> - WebChat 作为前端（localhost:18789，律所内网访问）
> - LanceDB 法律知识库
> - 4 个物理隔离 Agent：clerk (DeepSeek), plaintiff (Claude Sonnet), defendant (Claude Sonnet), judge (Claude Sonnet)
>
> **核心要求**:
> 1. auth-profiles.json 必须使用 `{"version": 1, "profiles": {"provider:default": {"type": "api_key", "provider": "...", "key": "..."}}}` 格式
> 2. 不使用 sessions_send 或 agentToAgent 做 Agent 间通信，完全依赖 Lobster 工作流编排
> 3. 原被告 workspace 物理隔离，信息只通过 Lobster step 的公开输出传递
> 4. 举证质证环节使用 Lobster 的 sub-workflow + loop 实现多轮对抗
> 5. 法官在辩论前必须归纳争议焦点（approval gate）
> 6. 判决前设置 approval gate 让律师确认
>
> **请输出以下内容**:
> 1. 完整的 `openclaw.json` 配置
> 2. 完整的 `docker-compose.yml`（如果使用 Docker 部署）
> 3. 4 个 Agent 的 auth-profiles.json 模板
> 4. 4 个 Agent 的 SOUL.md（中文，符合中国法庭设定）
> 5. `moot-court.lobster` 主工作流 和 `evidence-round.lobster` 子工作流
> 6. `init-case.sh` 案件初始化脚本
> 7. `ingest_law.py` 法律知识入库脚本（LanceDB + embedding）
> 8. 一个测试案件的 Markdown 示例文件（借款合同纠纷）
>
> 请确保代码可直接运行，不要使用占位符。分文件输出。

---
