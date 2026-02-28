#!/bin/bash
# install.sh — 安装 context-guard hook 到 ~/.claude/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/context-guard.sh"
HOOK_DIR="$HOME/.claude/hooks"
HOOK_DST="$HOOK_DIR/context-guard.sh"
SETTINGS="$HOME/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ─── 1. 复制 hook 脚本 ───
mkdir -p "$HOOK_DIR"

if [[ -f "$HOOK_DST" ]] && diff -q "$HOOK_SRC" "$HOOK_DST" &>/dev/null; then
    echo -e "${GREEN}✓${RESET} Hook 脚本已是最新: $HOOK_DST"
else
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    echo -e "${GREEN}✓${RESET} Hook 脚本已安装: $HOOK_DST"
fi

# ─── 2. 注册 hook 到 settings.json ───
HOOK_CMD="~/.claude/hooks/context-guard.sh"

if [[ ! -f "$SETTINGS" ]]; then
    # 创建最小 settings
    cat > "$SETTINGS" << EOF
{
  "hooks": {
    "PreToolUse": [{"hooks": [{"type": "command", "command": "$HOOK_CMD", "timeout": 10}]}],
    "PostToolUse": [{"hooks": [{"type": "command", "command": "$HOOK_CMD", "timeout": 10}]}]
  }
}
EOF
    echo -e "${GREEN}✓${RESET} 创建 settings.json 并注册 hooks"
else
    # 检查是否已注册
    NEEDS_UPDATE=false

    for EVENT in PreToolUse PostToolUse; do
        if ! jq -e ".hooks.${EVENT}" "$SETTINGS" &>/dev/null; then
            NEEDS_UPDATE=true
            break
        fi
        if ! jq -e ".hooks.${EVENT}[]?.hooks[]? | select(.command == \"$HOOK_CMD\")" "$SETTINGS" &>/dev/null; then
            NEEDS_UPDATE=true
            break
        fi
    done

    if $NEEDS_UPDATE; then
        # 用 jq 添加/更新 hooks
        HOOK_ENTRY=$(jq -n --arg cmd "$HOOK_CMD" '[{"hooks": [{"type": "command", "command": $cmd, "timeout": 10}]}]')

        TMP=$(mktemp)
        jq --argjson entry "$HOOK_ENTRY" '
            .hooks //= {} |
            .hooks.PreToolUse = (
                if (.hooks.PreToolUse // [] | map(.hooks[]?.command) | index("'"$HOOK_CMD"'"))
                then .hooks.PreToolUse
                else (.hooks.PreToolUse // []) + $entry
                end
            ) |
            .hooks.PostToolUse = (
                if (.hooks.PostToolUse // [] | map(.hooks[]?.command) | index("'"$HOOK_CMD"'"))
                then .hooks.PostToolUse
                else (.hooks.PostToolUse // []) + $entry
                end
            )
        ' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
        echo -e "${GREEN}✓${RESET} Hooks 已注册到 settings.json"
    else
        echo -e "${GREEN}✓${RESET} Hooks 已注册，无需更新"
    fi
fi

echo -e "\n${GREEN}安装完成！${RESET}"
echo -e "  Hook 脚本: $HOOK_DST"
echo -e "  配置文件: $SETTINGS"
echo -e "\n${YELLOW}配置:${RESET}"
echo -e "  CTX_WARN_TOKENS=150000     # 警告阈值（可通过环境变量覆盖）"
echo -e "  CTX_CRITICAL_TOKENS=170000 # 拒绝阈值（可通过环境变量覆盖）"
