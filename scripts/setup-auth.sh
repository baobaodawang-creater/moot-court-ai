#!/bin/bash
# Moot Court AI - 从 .env 生成 agent auth-profiles.json
# 用法: ./scripts/setup-auth.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$PROJECT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 未找到 .env: $ENV_FILE"
  echo "请先执行: cp .env.example .env 并填入 API Key"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [ -z "${DEEPSEEK_API_KEY:-}" ] || [ "$DEEPSEEK_API_KEY" = "sk-你的DeepSeek密钥" ]; then
  echo "❌ DEEPSEEK_API_KEY 未配置。请检查 .env"
  exit 1
fi

if [ -z "${DASHSCOPE_API_KEY:-}" ] || [ "$DASHSCOPE_API_KEY" = "sk-你的百炼密钥" ]; then
  echo "❌ DASHSCOPE_API_KEY 未配置。请检查 .env"
  exit 1
fi

write_profile() {
  local agent="$1"
  local provider_key="$2"
  local provider_name="$3"
  local api_key="$4"
  local target_dir="$PROJECT_DIR/agents/$agent/agent"
  local target_file="$target_dir/auth-profiles.json"

  mkdir -p "$target_dir"

  cat > "$target_file" <<EOF
{
  "version": 1,
  "profiles": {
    "$provider_key:default": {
      "type": "api_key",
      "provider": "$provider_name",
      "key": "$api_key"
    }
  },
  "usageStats": {}
}
EOF
}

echo "============================================"
echo "  🔐  生成 Agent 鉴权文件"
echo "============================================"

write_profile "clerk" "custom-api-deepseek-com" "custom-api-deepseek-com" "$DEEPSEEK_API_KEY"
echo "✅ clerk -> custom-api-deepseek-com"

write_profile "plaintiff" "custom-api-deepseek-com" "custom-api-deepseek-com" "$DEEPSEEK_API_KEY"
echo "✅ plaintiff -> custom-api-deepseek-com"

write_profile "judge" "custom-api-deepseek-com" "custom-api-deepseek-com" "$DEEPSEEK_API_KEY"
echo "✅ judge -> custom-api-deepseek-com"

write_profile "defendant" "custom-api-dashscope" "custom-api-dashscope" "$DASHSCOPE_API_KEY"
echo "✅ defendant -> custom-api-dashscope"

echo ""
echo "已写入:"
echo "  $PROJECT_DIR/agents/*/agent/auth-profiles.json"

