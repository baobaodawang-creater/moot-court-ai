#!/bin/bash
# Moot Court AI - 案件材料初始化
# 用法: ./scripts/init-case.sh <案件目录>
#
# 案件目录结构:
#   case-input/
#   ├── case-brief.md          # 案件概要（公共）
#   ├── complaint.md           # 起诉状（原告）
#   ├── defense.md             # 答辩状（被告）
#   ├── plaintiff-evidence/    # 原告证据
#   │   ├── evidence-001.md
#   │   └── evidence-list.md
#   ├── defendant-evidence/    # 被告证据
#   │   ├── evidence-001.md
#   │   └── evidence-list.md
#   ├── plaintiff-strategy.md  # 原告策略（可选）
#   └── defendant-strategy.md  # 被告策略（可选）

set -e

CASE_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$CASE_DIR" ]; then
    echo "用法: ./scripts/init-case.sh <案件目录>"
    echo ""
    echo "示例: ./scripts/init-case.sh test-cases/contract-dispute/"
    exit 1
fi

# 如果是相对路径，转为绝对路径
if [[ "$CASE_DIR" != /* ]]; then
    CASE_DIR="$PROJECT_DIR/$CASE_DIR"
fi

if [ ! -d "$CASE_DIR" ]; then
    echo "❌ 案件目录不存在: $CASE_DIR"
    exit 1
fi

PLAINTIFF_WS="$PROJECT_DIR/agents/plaintiff/workspace"
DEFENDANT_WS="$PROJECT_DIR/agents/defendant/workspace"
JUDGE_WS="$PROJECT_DIR/agents/judge/workspace"
CLERK_WS="$PROJECT_DIR/agents/clerk/workspace"

echo "============================================"
echo "  🏛️  案件材料初始化"
echo "============================================"
echo "  案件目录: $CASE_DIR"
echo ""

# 1. 清理旧数据
echo "[1/5] 清理旧案件数据..."
rm -f "$PLAINTIFF_WS/complaint.md"
rm -rf "$PLAINTIFF_WS/evidence/"
rm -f "$PLAINTIFF_WS/strategy.md"
rm -f "$DEFENDANT_WS/defense.md"
rm -rf "$DEFENDANT_WS/evidence/"
rm -f "$DEFENDANT_WS/strategy.md"
rm -f "$CLERK_WS/case-brief.md"
rm -f "$CLERK_WS/court-record.md"
rm -f "$JUDGE_WS/case-brief.md"
echo "   ✅ 已清理"

# 2. 分发原告材料
echo "[2/5] 分发原告材料..."
if [ -f "$CASE_DIR/complaint.md" ]; then
    cp "$CASE_DIR/complaint.md" "$PLAINTIFF_WS/"
    echo "   ✅ 起诉状"
else
    echo "   ⚠️  未找到 complaint.md"
fi

mkdir -p "$PLAINTIFF_WS/evidence"
if [ -d "$CASE_DIR/plaintiff-evidence" ]; then
    cp "$CASE_DIR/plaintiff-evidence/"* "$PLAINTIFF_WS/evidence/" 2>/dev/null || true
    PCOUNT=$(ls "$PLAINTIFF_WS/evidence/" 2>/dev/null | wc -l)
    echo "   ✅ 原告证据 ${PCOUNT} 份"
fi

if [ -f "$CASE_DIR/plaintiff-strategy.md" ]; then
    cp "$CASE_DIR/plaintiff-strategy.md" "$PLAINTIFF_WS/strategy.md"
    echo "   ✅ 原告策略"
fi

# 3. 分发被告材料
echo "[3/5] 分发被告材料..."
if [ -f "$CASE_DIR/defense.md" ]; then
    cp "$CASE_DIR/defense.md" "$DEFENDANT_WS/"
    echo "   ✅ 答辩状"
else
    echo "   ⚠️  未找到 defense.md"
fi

mkdir -p "$DEFENDANT_WS/evidence"
if [ -d "$CASE_DIR/defendant-evidence" ]; then
    cp "$CASE_DIR/defendant-evidence/"* "$DEFENDANT_WS/evidence/" 2>/dev/null || true
    DCOUNT=$(ls "$DEFENDANT_WS/evidence/" 2>/dev/null | wc -l)
    echo "   ✅ 被告证据 ${DCOUNT} 份"
fi

if [ -f "$CASE_DIR/defendant-strategy.md" ]; then
    cp "$CASE_DIR/defendant-strategy.md" "$DEFENDANT_WS/strategy.md"
    echo "   ✅ 被告策略"
fi

# 4. 分发公共材料
echo "[4/5] 分发公共材料..."
if [ -f "$CASE_DIR/case-brief.md" ]; then
    cp "$CASE_DIR/case-brief.md" "$CLERK_WS/"
    cp "$CASE_DIR/case-brief.md" "$JUDGE_WS/"
    echo "   ✅ 案件概要 -> 书记员 + 法官"
fi

# 5. 初始化庭审记录
echo "[5/5] 初始化庭审记录..."
CASE_NAME=$(basename "$CASE_DIR")
cat > "$CLERK_WS/court-record.md" << EOF
# 庭审记录

案件编号：${CASE_NAME}
初始化时间：$(date '+%Y-%m-%d %H:%M:%S')
状态：待开庭

---

EOF
echo "   ✅ 庭审记录已初始化"

echo ""
echo "============================================"
echo "  ✅ 案件材料初始化完成"
echo "============================================"
echo ""
echo "  原告材料: $PLAINTIFF_WS/"
echo "  被告材料: $DEFENDANT_WS/"
echo "  案件概要: $CLERK_WS/case-brief.md"
echo ""
echo "  下一步: 启动 Gateway 后在 WebChat 中触发庭审"
echo ""
