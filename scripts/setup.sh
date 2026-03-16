#!/bin/bash
# Moot Court AI - 一键初始化脚本
# 用法: ./scripts/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OPENCLAW_DIR="$HOME/.openclaw"

echo "============================================"
echo "  🏛️  Moot Court AI — 初始化部署"
echo "============================================"
echo ""

# 检查依赖
echo "[1/6] 检查依赖..."

if ! command -v node &> /dev/null; then
    echo "❌ 未找到 Node.js。请安装 Node.js 22+: https://nodejs.org"
    exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 22 ]; then
    echo "❌ Node.js 版本过低: $(node -v)。需要 22+。"
    exit 1
fi
echo "   ✅ Node.js $(node -v)"

if ! command -v openclaw &> /dev/null; then
    echo "   ⚠️  未找到 OpenClaw，正在安装..."
    npm install -g openclaw@latest
fi
echo "   ✅ OpenClaw $(openclaw --version 2>/dev/null || echo 'installed')"

if ! command -v python3 &> /dev/null; then
    echo "❌ 未找到 Python3。请安装 Python 3.10+。"
    exit 1
fi
echo "   ✅ Python $(python3 --version)"

# 检查 .env
echo ""
echo "[2/6] 检查 API Keys..."

if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "   ⚠️  .env 文件不存在，从模板创建..."
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    echo "   📝 请编辑 $PROJECT_DIR/.env 填入你的 API Keys，然后重新运行此脚本。"
    echo ""
    echo "   需要的 Keys:"
    echo "   - DEEPSEEK_API_KEY: https://platform.deepseek.com"
    echo "   - DASHSCOPE_API_KEY: https://bailian.console.aliyun.com"
    exit 1
fi

source "$PROJECT_DIR/.env"

if [ "$DEEPSEEK_API_KEY" = "sk-你的DeepSeek密钥" ] || [ -z "$DEEPSEEK_API_KEY" ]; then
    echo "❌ DEEPSEEK_API_KEY 未配置。请编辑 .env 文件。"
    exit 1
fi
echo "   ✅ DEEPSEEK_API_KEY 已配置 (${DEEPSEEK_API_KEY:0:10}...)"

if [ "$DASHSCOPE_API_KEY" = "sk-你的百炼密钥" ] || [ -z "$DASHSCOPE_API_KEY" ]; then
    echo "❌ DASHSCOPE_API_KEY 未配置。请编辑 .env 文件。"
    exit 1
fi
echo "   ✅ DASHSCOPE_API_KEY 已配置 (${DASHSCOPE_API_KEY:0:10}...)"

# 创建 OpenClaw Agent 目录
echo ""
echo "[3/6] 创建 Agent 目录结构..."

for AGENT in clerk plaintiff defendant judge; do
    mkdir -p "$OPENCLAW_DIR/agents/$AGENT/agent"
    echo "   ✅ $AGENT agent 目录已创建"
done

mkdir -p "$OPENCLAW_DIR/workflows"
mkdir -p "$OPENCLAW_DIR/memory/lancedb"

# 分发 auth-profiles.json
echo ""
echo "[4/6] 配置 Agent 鉴权..."

# clerk, plaintiff, judge -> DeepSeek
for AGENT in clerk plaintiff judge; do
    cat > "$OPENCLAW_DIR/agents/$AGENT/agent/auth-profiles.json" << EOF
{
  "version": 1,
  "profiles": {
    "custom-api-deepseek-com:default": {
      "type": "api_key",
      "provider": "custom-api-deepseek-com",
      "key": "$DEEPSEEK_API_KEY"
    }
  },
  "usageStats": {}
}
EOF
    echo "   ✅ $AGENT -> DeepSeek"
done

# defendant -> Dashscope/Qwen
cat > "$OPENCLAW_DIR/agents/defendant/agent/auth-profiles.json" << EOF
{
  "version": 1,
  "profiles": {
    "custom-api-dashscope:default": {
      "type": "api_key",
      "provider": "custom-api-dashscope",
      "key": "$DASHSCOPE_API_KEY"
    }
  },
  "usageStats": {}
}
EOF
echo "   ✅ defendant -> Qwen (Dashscope)"

# 部署配置文件
echo ""
echo "[5/6] 部署配置文件..."

# 复制 openclaw.json 并替换环境变量
sed -e "s|\${DEEPSEEK_API_KEY}|$DEEPSEEK_API_KEY|g" \
    -e "s|\${DASHSCOPE_API_KEY}|$DASHSCOPE_API_KEY|g" \
    "$PROJECT_DIR/openclaw.json" > "$OPENCLAW_DIR/openclaw.json"
echo "   ✅ openclaw.json"

# 复制工作流文件
cp "$PROJECT_DIR/workflows/"*.lobster "$OPENCLAW_DIR/workflows/" 2>/dev/null || true
echo "   ✅ Lobster 工作流文件"

# 验证
echo ""
echo "[6/6] 验证配置..."

if command -v openclaw &> /dev/null; then
    openclaw doctor 2>/dev/null && echo "   ✅ openclaw doctor 通过" || echo "   ⚠️  openclaw doctor 有警告（不影响使用）"
fi

echo ""
echo "============================================"
echo "  ✅ 初始化完成！"
echo "============================================"
echo ""
echo "下一步："
echo "  1. 准备案件材料:  ./scripts/init-case.sh test-cases/contract-dispute/"
echo "  2. 启动 Gateway:  openclaw gateway --port 18789"
echo "  3. 打开浏览器:    http://localhost:18789"
echo "  4. 在 WebChat 中输入: \"启动模拟法庭\""
echo ""
