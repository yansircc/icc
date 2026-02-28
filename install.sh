#!/bin/bash
# install.sh — Install context-guard hook to ~/.claude/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SRC="$SCRIPT_DIR/context-guard.sh"
HOOK_DIR="$HOME/.claude/hooks"
HOOK_DST="$HOOK_DIR/context-guard.sh"
SETTINGS="$HOME/.claude/settings.json"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# ─── 1. Copy hook script ───
mkdir -p "$HOOK_DIR"

if [[ -f "$HOOK_DST" ]] && diff -q "$HOOK_SRC" "$HOOK_DST" &>/dev/null; then
    echo -e "${GREEN}✓${RESET} Hook script is up to date: $HOOK_DST"
else
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    echo -e "${GREEN}✓${RESET} Hook script installed: $HOOK_DST"
fi

# ─── 2. Register hooks in settings.json ───
HOOK_CMD="~/.claude/hooks/context-guard.sh"

if [[ ! -f "$SETTINGS" ]]; then
    cat > "$SETTINGS" << EOF
{
  "hooks": {
    "PreToolUse": [{"hooks": [{"type": "command", "command": "$HOOK_CMD", "timeout": 10}]}],
    "PostToolUse": [{"hooks": [{"type": "command", "command": "$HOOK_CMD", "timeout": 10}]}]
  }
}
EOF
    echo -e "${GREEN}✓${RESET} Created settings.json and registered hooks"
else
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
        echo -e "${GREEN}✓${RESET} Hooks registered in settings.json"
    else
        echo -e "${GREEN}✓${RESET} Hooks already registered, no update needed"
    fi
fi

echo -e "\n${GREEN}Installation complete!${RESET}"
echo -e "  Hook script: $HOOK_DST"
echo -e "  Settings: $SETTINGS"
echo -e "\n${YELLOW}Configuration:${RESET}"
echo -e "  CTX_WARN_TOKENS=175000     # Warning threshold (override via env var)"
echo -e "  CTX_CRITICAL_TOKENS=190000 # Rejection threshold (override via env var)"
echo -e "\n${YELLOW}TTY mode env vars:${RESET}"
echo -e "  ICC_HANDOFF_PATH           # Set automatically by supervisor-tty; agent writes handoff to this path"
