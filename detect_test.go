package main

import (
	"sync/atomic"
	"testing"
	"time"
)

func TestShellPromptRe(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  bool
	}{
		{"zsh percent", "user@host ~ %", true},
		{"zsh percent with trailing space", "user@host ~ % ", true},
		{"bash dollar", "user@host:~$", true},
		{"bash dollar with space", "user@host:~$ ", true},
		{"bare percent", "%", true},
		{"bare dollar", "$", true},
		{"dollar in middle", "echo $HOME", false},
		{"percent in middle", "100% done", false},
		{"empty string", "", false},
		{"no prompt char", "user@host:~", false},
		{"multiline with prompt at end", "some output\nmore output\nuser@host ~ % ", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := shellPromptRe.MatchString(tt.input)
			if got != tt.want {
				t.Errorf("shellPromptRe.MatchString(%q) = %v, want %v", tt.input, got, tt.want)
			}
		})
	}
}

func TestPollUntil(t *testing.T) {
	t.Run("returns true when condition met immediately", func(t *testing.T) {
		got := pollUntil(func() bool { return true }, time.Second, 10*time.Millisecond)
		if !got {
			t.Error("expected true for immediately satisfied condition")
		}
	})

	t.Run("returns true when condition met after retries", func(t *testing.T) {
		var counter int32
		got := pollUntil(func() bool {
			return atomic.AddInt32(&counter, 1) >= 3
		}, time.Second, 10*time.Millisecond)
		if !got {
			t.Error("expected true after retries")
		}
		if c := atomic.LoadInt32(&counter); c < 3 {
			t.Errorf("expected at least 3 calls, got %d", c)
		}
	})

	t.Run("returns false on timeout", func(t *testing.T) {
		got := pollUntil(func() bool { return false }, 50*time.Millisecond, 10*time.Millisecond)
		if got {
			t.Error("expected false on timeout")
		}
	})
}
