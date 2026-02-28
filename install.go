package main

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

//go:embed context-guard.sh
var contextGuardSh []byte

const hookCmd = "~/.claude/hooks/context-guard.sh"

func runInstall() {
	home, err := os.UserHomeDir()
	if err != nil {
		errMsg("Cannot determine home directory: %v", err)
		os.Exit(1)
	}

	hookDir := filepath.Join(home, ".claude", "hooks")
	hookDst := filepath.Join(hookDir, "context-guard.sh")
	settingsPath := filepath.Join(home, ".claude", "settings.json")

	// 1. Install hook script
	os.MkdirAll(hookDir, 0755)

	existing, err := os.ReadFile(hookDst)
	if err == nil && string(existing) == string(contextGuardSh) {
		okMsg("Hook script is up to date: %s", hookDst)
	} else {
		if err := os.WriteFile(hookDst, contextGuardSh, 0755); err != nil {
			errMsg("Failed to write hook script: %v", err)
			os.Exit(1)
		}
		okMsg("Hook script installed: %s", hookDst)
	}

	// 2. Register hooks in settings.json
	registerHooks(settingsPath)

	fmt.Printf("\n%s%sInstallation complete!%s\n", colorGreen, colorBold, colorReset)
	fmt.Printf("  Hook script: %s\n", hookDst)
	fmt.Printf("  Settings: %s\n", settingsPath)
	fmt.Printf("\n%sConfiguration:%s\n", colorYellow, colorReset)
	fmt.Printf("  CTX_WARN_TOKENS=175000     # Warning threshold (override via env var)\n")
	fmt.Printf("  CTX_CRITICAL_TOKENS=190000 # Rejection threshold (override via env var)\n")
	fmt.Printf("\n%sTTY mode env vars:%s\n", colorYellow, colorReset)
	fmt.Printf("  ICC_HANDOFF_PATH           # Set automatically by icc; agent writes handoff to this path\n")
}

func registerHooks(settingsPath string) {
	hookEntry := []interface{}{
		map[string]interface{}{
			"hooks": []interface{}{
				map[string]interface{}{
					"type":    "command",
					"command": hookCmd,
					"timeout": 10,
				},
			},
		},
	}

	settings := map[string]interface{}{}

	data, err := os.ReadFile(settingsPath)
	if err == nil {
		if err := json.Unmarshal(data, &settings); err != nil {
			errMsg("Failed to parse %s: %v", settingsPath, err)
			os.Exit(1)
		}
	}

	hooks, _ := settings["hooks"].(map[string]interface{})
	if hooks == nil {
		hooks = map[string]interface{}{}
	}

	updated := false
	for _, event := range []string{"PreToolUse", "PostToolUse"} {
		if !hasHookCommand(hooks[event], hookCmd) {
			existing, _ := hooks[event].([]interface{})
			hooks[event] = append(existing, hookEntry[0])
			updated = true
		}
	}

	if !updated {
		okMsg("Hooks already registered, no update needed")
		return
	}

	settings["hooks"] = hooks

	out, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		errMsg("Failed to marshal settings: %v", err)
		os.Exit(1)
	}
	if err := os.WriteFile(settingsPath, append(out, '\n'), 0644); err != nil {
		errMsg("Failed to write %s: %v", settingsPath, err)
		os.Exit(1)
	}
	okMsg("Hooks registered in settings.json")
}

// hasHookCommand checks if the event's hook array already contains our command.
func hasHookCommand(eventVal interface{}, cmd string) bool {
	entries, ok := eventVal.([]interface{})
	if !ok {
		return false
	}
	for _, entry := range entries {
		e, ok := entry.(map[string]interface{})
		if !ok {
			continue
		}
		innerHooks, ok := e["hooks"].([]interface{})
		if !ok {
			continue
		}
		for _, h := range innerHooks {
			hm, ok := h.(map[string]interface{})
			if !ok {
				continue
			}
			if hm["command"] == cmd {
				return true
			}
		}
	}
	return false
}
