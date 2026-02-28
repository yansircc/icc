#!/bin/bash
# supervisor.sh — infinite-claude 主循环
# 启动 claude session → 解析 stream-json → context 耗尽时接力新 session
set -euo pipefail

# ─── 默认配置 ───
MODEL="${MODEL:-sonnet}"
MAX_SESSIONS="${MAX_SESSIONS:-10}"
CTX_WARN_TOKENS="${CTX_WARN_TOKENS:-150000}"
CTX_CRITICAL_TOKENS="${CTX_CRITICAL_TOKENS:-170000}"
export CTX_WARN_TOKENS CTX_CRITICAL_TOKENS

# ─── 参数解析 ───
TASK=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)       MODEL="$2"; shift 2 ;;
        --max-sessions) MAX_SESSIONS="$2"; shift 2 ;;
        --warn-tokens)  CTX_WARN_TOKENS="$2"; export CTX_WARN_TOKENS; shift 2 ;;
        --critical-tokens) CTX_CRITICAL_TOKENS="$2"; export CTX_CRITICAL_TOKENS; shift 2 ;;
        --help|-h)
            cat <<'USAGE'
Usage: supervisor.sh [OPTIONS] "TASK DESCRIPTION"

Options:
  --model MODEL          Claude model to use (default: sonnet)
  --max-sessions N       Maximum relay sessions (default: 10)
  --warn-tokens N        Context warning threshold (default: 150000)
  --critical-tokens N    Context critical/deny threshold (default: 170000)

Environment variables CTX_WARN_TOKENS, CTX_CRITICAL_TOKENS also work.

Example:
  bash supervisor.sh --model haiku --max-sessions 3 \
    "Write a Python HTTP server with GET/POST endpoints"
USAGE
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            TASK="$1"; shift ;;
    esac
done

if [[ -z "$TASK" ]]; then
    echo "Error: no task provided. Usage: supervisor.sh [OPTIONS] \"TASK\"" >&2
    exit 1
fi

# ─── 避免嵌套检测 ───
unset CLAUDECODE 2>/dev/null || true

# ─── 系统指令 ───
SYSTEM_INSTRUCTION="
[IMPORTANT SYSTEM INSTRUCTION]
You are running inside an infinite-claude supervisor that relays sessions.
When you receive a context warning (⚠ Context 已用...), you MUST:
1. Finish your current immediate step
2. Output a HANDOFF summary as your final message with this exact format:

## Handoff Summary
### Completed
- (what was done)
### In Progress
- (what was being worked on)
### Remaining
- (what still needs to be done)
### Key Files
- (important file paths)
### Notes
- (any context the next session needs)
"

# ─── 颜色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── 统计 ───
TOTAL_COST=0
TOTAL_INPUT=0
TOTAL_OUTPUT=0
SESSION_COUNT=0

# ─── 辅助函数 ───
add_cost() {
    TOTAL_COST=$(python3 -c "print(round($TOTAL_COST + ${1:-0}, 6))")
}
add_tokens() {
    TOTAL_INPUT=$(( TOTAL_INPUT + ${1:-0} ))
    TOTAL_OUTPUT=$(( TOTAL_OUTPUT + ${2:-0} ))
}

# ─── 主循环 ───
CONTEXT=""

for (( i=1; i<=MAX_SESSIONS; i++ )); do
    SESSION_COUNT=$i
    echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
    echo -e "${BOLD}${BLUE}  Session $i / $MAX_SESSIONS  (model: $MODEL)${RESET}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}\n"

    # 构造 prompt
    if [[ $i -eq 1 ]]; then
        PROMPT="${TASK}

${SYSTEM_INSTRUCTION}"
    else
        PROMPT="继续工作。上一个 session 的交接信息如下：

${CONTEXT}

请根据交接信息继续完成任务。原始任务：${TASK}

${SYSTEM_INSTRUCTION}"
    fi

    # 运行 claude，逐行解析 stream-json
    RESULT=""
    TOOL_USE_COUNT=0
    SESSION_COST=0
    SESSION_INPUT=0
    SESSION_OUTPUT=0

    while IFS= read -r line; do
        # 跳过空行
        [[ -z "$line" ]] && continue

        TYPE=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || continue

        case "$TYPE" in
            assistant)
                # 提取文本内容
                TEXT=$(echo "$line" | jq -r '
                    .message.content[]? |
                    select(.type == "text") |
                    .text // empty
                ' 2>/dev/null)
                if [[ -n "$TEXT" ]]; then
                    echo -e "${CYAN}${TEXT}${RESET}"
                fi
                ;;
            tool_use)
                TOOL_USE_COUNT=$(( TOOL_USE_COUNT + 1 ))
                TNAME=$(echo "$line" | jq -r '.tool_name // "unknown"' 2>/dev/null)
                echo -e "  ${YELLOW}🔧 [$TNAME]${RESET}"
                ;;
            tool_result)
                # 静默，不打印工具结果（太长）
                ;;
            result)
                # 最终结果
                RESULT=$(echo "$line" | jq -r '.result // empty' 2>/dev/null)
                SC=$(echo "$line" | jq -r '.cost_usd // 0' 2>/dev/null)
                SI=$(echo "$line" | jq -r '.usage.input_tokens // 0' 2>/dev/null)
                SO=$(echo "$line" | jq -r '.usage.output_tokens // 0' 2>/dev/null)
                SESSION_COST=$SC
                SESSION_INPUT=$SI
                SESSION_OUTPUT=$SO
                ;;
        esac
    done < <(claude -p --model "$MODEL" --verbose --output-format stream-json "$PROMPT" 2>/dev/null)

    # 累计统计
    add_cost "$SESSION_COST"
    add_tokens "$SESSION_INPUT" "$SESSION_OUTPUT"

    echo -e "\n${GREEN}── Session $i 完成 ──${RESET}"
    echo -e "  工具调用: ${TOOL_USE_COUNT}  |  费用: \$${SESSION_COST}  |  tokens: ${SESSION_INPUT} in / ${SESSION_OUTPUT} out"

    # 交接内容
    CONTEXT="$RESULT"

    # 终止判断：result 很短且没用工具 → 任务完成
    RESULT_LEN=${#RESULT}
    if (( TOOL_USE_COUNT == 0 )) && (( RESULT_LEN < 200 )); then
        echo -e "\n${GREEN}${BOLD}✓ 任务似乎已完成（session 未使用工具且输出简短）${RESET}"
        break
    fi

    # result 为空 → 异常退出
    if [[ -z "$RESULT" ]]; then
        echo -e "\n${RED}✗ Session 返回空结果，停止${RESET}"
        break
    fi
done

# ─── 最终统计 ───
echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
echo -e "${BOLD}${BLUE}  infinite-claude 完成${RESET}"
echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
echo -e "  总 session 数: ${SESSION_COUNT}"
echo -e "  总费用: \$${TOTAL_COST}"
echo -e "  总 tokens: ${TOTAL_INPUT} in / ${TOTAL_OUTPUT} out"
echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
