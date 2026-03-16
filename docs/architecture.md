# 架构设计文档

## 设计原则

### 1. 确定性编排，创造性执行
Lobster 工作流引擎控制庭审流程（谁先说、谁后说），LLM 只在每个步骤内做创造性工作（法律论述）。绝不让 LLM 自己决定流程走向。

### 2. 物理隔离的信息屏障
原告和被告各有独立的 workspace 目录，通过 OpenClaw 的 `agentDir` + `workspace` 配置实现。信息只能通过 Lobster step 的公开输出（stdout/JSON）在 Agent 之间传递。

### 3. 红蓝差异化
原告（DeepSeek-R1）和被告（Qwen-Max）刻意使用不同提供商的模型，利用模型间的推理偏向差异产生更真实的对抗效果。

## 关键技术选型

### 为什么不用 sessions_send / agentToAgent？
- `sessions_send` 的 ping-pong 机制最多 5 轮，无法覆盖完整庭审
- LLM 决定流程会引入不确定性（Agent 可能跳过环节或帮对方说话）
- `agentToAgent` 与 `sessions_spawn` 存在已知冲突 (GitHub issue #5813)

### 为什么用 Lobster？
- YAML 定义的确定性 pipeline
- 内置 approval gate（法官归纳焦点和判决前需要人工确认）
- 支持 sub-workflow + loop（举证质证可循环多轮）
- 通过 `llm-task` 插件调用特定 Agent 的 LLM

### 为什么用 WebChat 而不是 Telegram？
- Telegram Bot API 不投递 Bot 消息给同群其他 Bot
- 中国大陆律所无法稳定访问 Telegram
- WebChat 是 OpenClaw 内置通道，localhost 直连，零配置

## 数据流

```
案件材料 (Markdown)
    │
    ├── complaint.md ──→ plaintiff/workspace/ (仅原告可见)
    ├── defense.md   ──→ defendant/workspace/ (仅被告可见)
    └── case-brief.md ──→ clerk + judge workspace (公共)
    
庭审过程中的信息流:
    clerk.stdout ──→ plaintiff (开庭通知)
    plaintiff.stdout ──→ defendant (原告主张, 通过 Lobster step)
    defendant.stdout ──→ plaintiff (被告抗辩, 通过 Lobster step)
    [双方 stdout] ──→ judge (全部公开记录)
    judge.stdout ──→ [最终输出] (判决书 + 风险报告)
    
注意: 原告的 strategy.md 永远不会出现在 Lobster 的任何 step 输出中
      被告的 strategy.md 同理
```

## 模型配置参考

| 提供商 | API Base URL | 无需 VPN | 定价 (百万token) |
|--------|-------------|---------|-----------------|
| DeepSeek | api.deepseek.com/v1 | ✅ | ~¥1-2 (chat), ~¥4 (reasoner) |
| 阿里云百炼 | dashscope.aliyuncs.com/compatible-mode/v1 | ✅ | ~¥0.8-20 (按模型) |
| 硅基流动 | api.siliconflow.cn/v1 | ✅ | 免费额度 + 按需 |
| 火山引擎 | ark.cn-beijing.volces.com/api/v3 | ✅ | 按需 |
