package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRenderSystemPrompt(t *testing.T) {
	path := "/tmp/icc-handoff-abc123.md"
	got := renderSystemPrompt(path)

	t.Run("contains handoff path", func(t *testing.T) {
		if !strings.Contains(got, path) {
			t.Errorf("prompt does not contain handoff path %q", path)
		}
	})

	t.Run("contains ICC relay header", func(t *testing.T) {
		if !strings.Contains(got, "ICC RELAY PROTOCOL") {
			t.Error("prompt missing ICC RELAY PROTOCOL header")
		}
	})

	t.Run("contains handoff format questions", func(t *testing.T) {
		for _, q := range []string{"Q0:", "Q1:", "Q2:", "Q3:", "Q4:"} {
			if !strings.Contains(got, q) {
				t.Errorf("prompt missing handoff question %s", q)
			}
		}
	})

	t.Run("contains Write tool instruction", func(t *testing.T) {
		if !strings.Contains(got, "Write tool") {
			t.Error("prompt missing Write tool instruction")
		}
	})
}

func TestPipeSystemPrompt(t *testing.T) {
	got := pipeSystemPrompt()

	t.Run("contains relay protocol", func(t *testing.T) {
		if !strings.Contains(got, "ICC RELAY PROTOCOL") {
			t.Error("prompt missing ICC RELAY PROTOCOL header")
		}
	})

	t.Run("contains handoff format", func(t *testing.T) {
		if !strings.Contains(got, "Q0:") {
			t.Error("prompt missing Q0 handoff question")
		}
	})

	t.Run("contains autonomous rule", func(t *testing.T) {
		if !strings.Contains(got, "AUTONOMOUS") {
			t.Error("prompt missing AUTONOMOUS rule")
		}
	})

	t.Run("does not contain file path instructions", func(t *testing.T) {
		if strings.Contains(got, "ICC_HANDOFF_PATH") {
			t.Error("pipe prompt should not reference ICC_HANDOFF_PATH")
		}
	})
}

func TestBuildContinuationPrompt(t *testing.T) {
	t.Run("embeds session number and task", func(t *testing.T) {
		got := buildContinuationPrompt(3, "Build a REST API", "handoff text here")

		if !strings.Contains(got, "session 3") {
			t.Error("prompt missing session number")
		}
		if !strings.Contains(got, "session 2") {
			t.Error("prompt missing previous session reference")
		}
		if !strings.Contains(got, "Build a REST API") {
			t.Error("prompt missing task")
		}
		if !strings.Contains(got, "handoff text here") {
			t.Error("prompt missing handoff content")
		}
	})

	t.Run("reads handoff from file when path exists", func(t *testing.T) {
		dir := t.TempDir()
		handoffFile := filepath.Join(dir, "handoff.md")
		os.WriteFile(handoffFile, []byte("## Q0: file-based handoff content"), 0644)

		got := buildContinuationPrompt(2, "my task", handoffFile)

		if !strings.Contains(got, "file-based handoff content") {
			t.Error("prompt should contain file content when handoff path is a valid file")
		}
		if strings.Contains(got, handoffFile) {
			t.Error("prompt should contain file content, not the file path")
		}
	})

	t.Run("uses raw string when file does not exist", func(t *testing.T) {
		got := buildContinuationPrompt(2, "my task", "raw handoff notes")

		if !strings.Contains(got, "raw handoff notes") {
			t.Error("prompt should fall back to raw string when file doesn't exist")
		}
	})

	t.Run("contains autonomous instruction", func(t *testing.T) {
		got := buildContinuationPrompt(2, "task", "handoff")
		if !strings.Contains(got, "AUTONOMOUS") {
			t.Error("continuation prompt missing AUTONOMOUS instruction")
		}
	})
}
