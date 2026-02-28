package main

import (
	"os"
	"testing"
)

func TestEnvOrDefault(t *testing.T) {
	const key = "ICC_TEST_ENV_OR_DEFAULT"

	t.Run("returns env value when set", func(t *testing.T) {
		os.Setenv(key, "custom")
		defer os.Unsetenv(key)
		if got := envOrDefault(key, "fallback"); got != "custom" {
			t.Errorf("got %q, want %q", got, "custom")
		}
	})

	t.Run("returns fallback when unset", func(t *testing.T) {
		os.Unsetenv(key)
		if got := envOrDefault(key, "fallback"); got != "fallback" {
			t.Errorf("got %q, want %q", got, "fallback")
		}
	})

	t.Run("returns fallback when empty", func(t *testing.T) {
		os.Setenv(key, "")
		defer os.Unsetenv(key)
		if got := envOrDefault(key, "fallback"); got != "fallback" {
			t.Errorf("got %q, want %q", got, "fallback")
		}
	})
}

func TestEnvIntOrDefault(t *testing.T) {
	const key = "ICC_TEST_ENV_INT"

	t.Run("returns parsed int when valid", func(t *testing.T) {
		os.Setenv(key, "42")
		defer os.Unsetenv(key)
		if got := envIntOrDefault(key, 10); got != 42 {
			t.Errorf("got %d, want %d", got, 42)
		}
	})

	t.Run("returns fallback for non-numeric string", func(t *testing.T) {
		os.Setenv(key, "notanumber")
		defer os.Unsetenv(key)
		if got := envIntOrDefault(key, 10); got != 10 {
			t.Errorf("got %d, want %d", got, 10)
		}
	})

	t.Run("returns fallback when unset", func(t *testing.T) {
		os.Unsetenv(key)
		if got := envIntOrDefault(key, 99); got != 99 {
			t.Errorf("got %d, want %d", got, 99)
		}
	})

	t.Run("returns fallback for empty string", func(t *testing.T) {
		os.Setenv(key, "")
		defer os.Unsetenv(key)
		if got := envIntOrDefault(key, 7); got != 7 {
			t.Errorf("got %d, want %d", got, 7)
		}
	})
}

func TestRequireArg(t *testing.T) {
	t.Run("returns next argument", func(t *testing.T) {
		args := []string{"--model", "haiku"}
		if got := requireArg(args, 0, "--model"); got != "haiku" {
			t.Errorf("got %q, want %q", got, "haiku")
		}
	})
}
