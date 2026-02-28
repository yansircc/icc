#!/bin/bash
# context-guard.sh — Context 监控 hook
# PostToolUse @ WARN: 每次都 inject 提醒剩余 token
# PreToolUse  @ CRITICAL: deny 探索类工具，仅放行 Read/Write/Edit/NotebookEdit
set -euo pipefail

INPUT=$(cat)
WARN=${CTX_WARN_TOKENS:-150000}
CRITICAL=${CTX_CRITICAL_TOKENS:-170000}

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')

[[ ! -f "$TRANSCRIPT" ]] && exit 0

# 从 transcript 提取最新 context 用量
CTX=$(python3 - "$TRANSCRIPT" << 'PY'
import json, sys
last = 0
for line in open(sys.argv[1]):
    d = json.loads(line)
    if d.get("type") != "assistant":
        continue
    u = d.get("message", {}).get("usage", {})
    if not u or u.get("output_tokens", 0) <= 20:
        continue
    last = (u.get("input_tokens", 0)
            + u.get("cache_creation_input_tokens", 0)
            + u.get("cache_read_input_tokens", 0)
            + u.get("output_tokens", 0))
print(last)
PY
)

# PreToolUse @ CRITICAL: deny 探索类工具
if [[ "$HOOK_EVENT" == "PreToolUse" ]] && (( CTX >= CRITICAL )); then
    case "$TOOL_NAME" in
        Write|Edit|Read|NotebookEdit) exit 0 ;;
    esac
    jq -n --arg r "Context ${CTX} tokens 已超上限 ${CRITICAL}。仅允许 Read/Write/Edit。请立即总结当前进度和未完成事项作为最终输出。" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
fi

# PostToolUse @ WARN: inject 提醒
if [[ "$HOOK_EVENT" == "PostToolUse" ]] && (( CTX >= WARN )); then
    REMAIN=$(( CRITICAL - CTX ))
    jq -n --arg c "⚠ Context 已用 ${CTX} tokens，距硬上限还剩约 ${REMAIN} tokens。建议尽快完成手头工作，然后总结进度和未完成事项作为最终输出。" \
      '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
    exit 0
fi

exit 0
