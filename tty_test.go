package main

import (
	"encoding/hex"
	"os"
	"path/filepath"
	"testing"
)

func TestSplitLines(t *testing.T) {
	tests := []struct {
		name string
		in   string
		want []string
	}{
		{"empty string", "", nil},
		{"single line no newline", "hello", []string{"hello"}},
		{"single line with newline", "hello\n", []string{"hello"}},
		{"multiple lines", "a\nb\nc\n", []string{"a", "b", "c"}},
		{"no trailing newline", "a\nb\nc", []string{"a", "b", "c"}},
		{"consecutive newlines", "a\n\nb\n", []string{"a", "", "b"}},
		{"only newlines", "\n\n", []string{"", ""}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := splitLines(tt.in)
			if len(got) != len(tt.want) {
				t.Fatalf("splitLines(%q) returned %d lines %v, want %d lines %v",
					tt.in, len(got), got, len(tt.want), tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Errorf("line %d: got %q, want %q", i, got[i], tt.want[i])
				}
			}
		})
	}
}

func TestFileExists(t *testing.T) {
	t.Run("returns true for existing file", func(t *testing.T) {
		dir := t.TempDir()
		path := filepath.Join(dir, "exists.txt")
		if err := writeTestFile(path, "content"); err != nil {
			t.Fatal(err)
		}
		if !fileExists(path) {
			t.Error("expected true for existing file")
		}
	})

	t.Run("returns false for nonexistent path", func(t *testing.T) {
		if fileExists("/nonexistent/path/file.txt") {
			t.Error("expected false for nonexistent path")
		}
	})

	t.Run("returns true for directory", func(t *testing.T) {
		dir := t.TempDir()
		if !fileExists(dir) {
			t.Error("expected true for existing directory")
		}
	})
}

func TestRandomHex(t *testing.T) {
	tests := []struct {
		n       int
		wantLen int
	}{
		{1, 2},
		{3, 6},
		{8, 16},
	}

	for _, tt := range tests {
		t.Run("", func(t *testing.T) {
			got := randomHex(tt.n)
			if len(got) != tt.wantLen {
				t.Errorf("randomHex(%d) length = %d, want %d", tt.n, len(got), tt.wantLen)
			}
			if _, err := hex.DecodeString(got); err != nil {
				t.Errorf("randomHex(%d) = %q, not valid hex: %v", tt.n, got, err)
			}
		})
	}

	t.Run("produces unique values", func(t *testing.T) {
		a := randomHex(8)
		b := randomHex(8)
		if a == b {
			t.Errorf("two calls returned identical values: %q", a)
		}
	})
}

func writeTestFile(path, content string) error {
	return os.WriteFile(path, []byte(content), 0644)
}
