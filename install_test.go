package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestHasHookCommand(t *testing.T) {
	cmd := "~/.claude/hooks/context-guard.sh"

	t.Run("nil event returns false", func(t *testing.T) {
		if hasHookCommand(nil, cmd) {
			t.Error("expected false for nil event")
		}
	})

	t.Run("empty array returns false", func(t *testing.T) {
		if hasHookCommand([]interface{}{}, cmd) {
			t.Error("expected false for empty array")
		}
	})

	t.Run("matching command returns true", func(t *testing.T) {
		event := []interface{}{
			map[string]interface{}{
				"hooks": []interface{}{
					map[string]interface{}{
						"type":    "command",
						"command": cmd,
						"timeout": 10,
					},
				},
			},
		}
		if !hasHookCommand(event, cmd) {
			t.Error("expected true when command matches")
		}
	})

	t.Run("different command returns false", func(t *testing.T) {
		event := []interface{}{
			map[string]interface{}{
				"hooks": []interface{}{
					map[string]interface{}{
						"type":    "command",
						"command": "other-script.sh",
					},
				},
			},
		}
		if hasHookCommand(event, cmd) {
			t.Error("expected false for non-matching command")
		}
	})

	t.Run("nested among multiple entries", func(t *testing.T) {
		event := []interface{}{
			map[string]interface{}{
				"hooks": []interface{}{
					map[string]interface{}{"command": "other.sh"},
				},
			},
			map[string]interface{}{
				"hooks": []interface{}{
					map[string]interface{}{"command": cmd},
				},
			},
		}
		if !hasHookCommand(event, cmd) {
			t.Error("expected true when command is in second entry")
		}
	})

	t.Run("wrong structure returns false", func(t *testing.T) {
		event := []interface{}{"not a map"}
		if hasHookCommand(event, cmd) {
			t.Error("expected false for wrong structure")
		}
	})
}

func TestRegisterHooks(t *testing.T) {
	t.Run("creates settings from scratch", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "settings.json")

		registerHooks(path)

		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("failed to read settings: %v", err)
		}

		var settings map[string]interface{}
		if err := json.Unmarshal(data, &settings); err != nil {
			t.Fatalf("invalid JSON: %v", err)
		}

		hooks, ok := settings["hooks"].(map[string]interface{})
		if !ok {
			t.Fatal("settings missing hooks key")
		}

		for _, event := range []string{"PreToolUse", "PostToolUse"} {
			if !hasHookCommand(hooks[event], hookCmd) {
				t.Errorf("hook not registered for %s", event)
			}
		}
	})

	t.Run("preserves existing settings", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "settings.json")

		existing := map[string]interface{}{
			"customKey": "customValue",
		}
		data, _ := json.Marshal(existing)
		os.WriteFile(path, data, 0644)

		registerHooks(path)

		result, _ := os.ReadFile(path)
		var settings map[string]interface{}
		json.Unmarshal(result, &settings)

		if settings["customKey"] != "customValue" {
			t.Error("existing settings were not preserved")
		}
	})

	t.Run("idempotent — does not duplicate hooks", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "settings.json")

		registerHooks(path)
		registerHooks(path)

		data, _ := os.ReadFile(path)
		var settings map[string]interface{}
		json.Unmarshal(data, &settings)

		hooks := settings["hooks"].(map[string]interface{})
		preToolUse := hooks["PreToolUse"].([]interface{})

		if len(preToolUse) != 1 {
			t.Errorf("expected 1 PreToolUse entry after double register, got %d", len(preToolUse))
		}
	})
}
