#!/bin/bash
# Moot Court AI - 命令行运行庭审工作流并导出判决书
# 用法: ./scripts/run-trial.sh [case_id]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$PROJECT_DIR/.env"
WORKFLOW_FILE="$PROJECT_DIR/workflows/moot-court.lobster"
CASE_BRIEF_PATH="$PROJECT_DIR/agents/clerk/workspace/case-brief.md"
PLAINTIFF_COMPLAINT="$PROJECT_DIR/agents/plaintiff/workspace/complaint.md"
OUTPUT_DIR="$PROJECT_DIR/output"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
CASE_ID="${1:-trial-$TIMESTAMP}"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 未找到 .env: $ENV_FILE"
  echo "请先执行: cp .env.example .env 并填入 API Key"
  exit 1
fi

if [ ! -f "$WORKFLOW_FILE" ]; then
  echo "❌ 未找到工作流文件: $WORKFLOW_FILE"
  exit 1
fi

if [ ! -f "$PLAINTIFF_COMPLAINT" ]; then
  echo "❌ 未检测到案件材料已分发：缺少 $PLAINTIFF_COMPLAINT"
  echo "请先执行: ./scripts/init-case.sh <案件目录>"
  exit 1
fi

if [ ! -f "$CASE_BRIEF_PATH" ]; then
  echo "❌ 缺少案件概要: $CASE_BRIEF_PATH"
  echo "请先执行: ./scripts/init-case.sh <案件目录>"
  exit 1
fi

if ! command -v lobster >/dev/null 2>&1; then
  echo "❌ 未找到 lobster 命令。请先安装并配置 OpenClaw/Lobster。"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
RAW_OUTPUT_FILE="$OUTPUT_DIR/${CASE_ID}-raw-${TIMESTAMP}.log"
JUDGMENT_FILE="$OUTPUT_DIR/${CASE_ID}-judgment-${TIMESTAMP}.md"

ARGS_JSON="{\"case_id\":\"$CASE_ID\",\"case_brief_path\":\"$CASE_BRIEF_PATH\"}"

echo "============================================"
echo "  🏛️  启动模拟庭审"
echo "============================================"
echo "  case_id:         $CASE_ID"
echo "  case_brief_path: $CASE_BRIEF_PATH"
echo "  workflow:        $WORKFLOW_FILE"
echo ""

set +e
lobster run "$WORKFLOW_FILE" --args-json "$ARGS_JSON" | tee "$RAW_OUTPUT_FILE"
run_status=${PIPESTATUS[0]}
set -e

if [ "$run_status" -ne 0 ]; then
  echo "⚠️  使用 --args-json 运行失败，尝试 --arg 形式重试..."
  set +e
  lobster run "$WORKFLOW_FILE" --arg case_id="$CASE_ID" --arg case_brief_path="$CASE_BRIEF_PATH" | tee "$RAW_OUTPUT_FILE"
  run_status=${PIPESTATUS[0]}
  set -e
fi

if [ "$run_status" -ne 0 ]; then
  echo "❌ 庭审执行失败。原始输出已保存：$RAW_OUTPUT_FILE"
  exit "$run_status"
fi

python3 - "$RAW_OUTPUT_FILE" "$JUDGMENT_FILE" <<'PY'
import json
import re
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
judgment_path = Path(sys.argv[2])
text = raw_path.read_text(encoding="utf-8", errors="ignore")

def try_json_parse(s):
    s = s.strip()
    if not s:
        return None
    try:
        return json.loads(s)
    except Exception:
        return None

data = try_json_parse(text)
if data is None:
    # 尝试提取最后一个 JSON 对象
    matches = re.findall(r"\{(?:.|\n)*\}", text)
    for candidate in reversed(matches):
        parsed = try_json_parse(candidate)
        if parsed is not None:
            data = parsed
            break

def find_judgment(obj):
    if isinstance(obj, dict):
        judgment = obj.get("judgment")
        if isinstance(judgment, str) and judgment.strip():
            return judgment
        jv = obj.get("judge_verdict")
        if isinstance(jv, dict):
            nested = find_judgment(jv)
            if nested:
                return nested
        for v in obj.values():
            nested = find_judgment(v)
            if nested:
                return nested
    elif isinstance(obj, list):
        for item in obj:
            nested = find_judgment(item)
            if nested:
                return nested
    return None

judgment_text = find_judgment(data) if data is not None else None

if not judgment_text:
    judgment_text = (
        "# 判决书提取失败\n\n"
        "未能从工作流输出中自动提取 `judgment` 字段。\n"
        "请查看同目录 raw 日志文件手动确认结果。\n"
    )

judgment_path.write_text(judgment_text.rstrip() + "\n", encoding="utf-8")
print(f"JUDGMENT_SAVED={judgment_path}")
PY

echo ""
echo "✅ 庭审已完成"
echo "📄 原始输出: $RAW_OUTPUT_FILE"
echo "📄 判决书:   $JUDGMENT_FILE"

