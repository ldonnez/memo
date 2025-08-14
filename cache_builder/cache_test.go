package cache_builder

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func setupGPG(t *testing.T) (string, []string) {
	t.Helper()

	gnupgHome := t.TempDir()
	os.Setenv("GNUPGHOME", gnupgHome)

	keyParams := `
		Key-Type: default
		Key-Length: 2048
		Subkey-Type: default
		Name-Real: Test User
		Name-Email: test@example.com
		Expire-Date: 1d
		%no-protection
		%commit
	`
	cmd := exec.Command("gpg", "--batch", "--gen-key")
	cmd.Stdin = strings.NewReader(keyParams)

	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("failed to generate test key: %s\n%s", err, out)
	}

	keys := []string{
		"test@example.com",
	}

	return gnupgHome, keys
}

func TestGPGKeyExists(t *testing.T) {
	gnupgHome, keyIDs := setupGPG(t)
	os.Setenv("GNUPGHOME", gnupgHome)

	if !gpgKeyExists(keyIDs[0]) {
		t.Errorf("expected gpgKeyExists(%q) to return true", keyIDs[0])
	}

	if gpgKeyExists("nonexistent@example.com") {
		t.Error("expected gpgKeyExists for missing key to return false")
	}
}

func TestCanDecrypt(t *testing.T) {
	gnupgHome, keyIDs := setupGPG(t)
	os.Setenv("GNUPGHOME", gnupgHome)

	tmpDir := t.TempDir()
	encFile := filepath.Join(tmpDir, "test.gpg")
	plaintext := "this is a test"

	// Create an encrypted file we can decrypt
	encryptNote(t, keyIDs, plaintext, encFile)

	if !canDecrypt(encFile) {
		t.Error("expected canDecrypt to return true for valid encrypted file")
	}

	// Create a file we cannot decrypt (random content)
	unreadableFile := filepath.Join(tmpDir, "random.gpg")
	if err := os.WriteFile(unreadableFile, []byte("not actually gpg"), 0644); err != nil {
		t.Fatal(err)
	}

	if canDecrypt(unreadableFile) {
		t.Error("expected canDecrypt to return false for invalid GPG file")
	}
}

func encryptNote(t *testing.T, recipients []string, plaintext string, dest string) {
	t.Helper()

	args := []string{"--yes", "--batch", "--quiet"}

	for _, recipient := range recipients {
		args = append(args, "--recipient", recipient)
	}

	args = append(args, "--encrypt", "--output", dest)

	cmd := exec.Command("gpg", args...)
	cmd.Stdin = strings.NewReader(plaintext)

	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("failed to encrypt note: %s\n%s", err, out)
	}
}

func TestUpdateAllAndLoad(t *testing.T) {
	_, keyIDs := setupGPG(t)
	notesDir := t.TempDir()
	cacheFile := filepath.Join(t.TempDir(), "notes.cache")

	// Create encrypted note
	notePath := filepath.Join(notesDir, "note1.gpg")
	encryptNote(t, keyIDs, "Hello world\nSecond line", notePath)

	// Run UpdateAll
	changed := UpdateAll(notesDir, cacheFile, keyIDs)
	if changed == 0 {
		t.Fatal("expected changes, got 0")
	}

	// Decrypt cache and verify content
	entries := DecryptAndLoad(cacheFile)
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}

	if entries[0].Content != "Hello world" || entries[1].Content != "Second line" {
		t.Errorf("unexpected cache content: %+v", entries)
	}

	// Run UpdateAll again without changes
	changed = UpdateAll(notesDir, cacheFile, keyIDs)
	if changed != 0 {
		t.Errorf("expected 0 changes on second run, got %d", changed)
	}

	// Add another note
	notePath2 := filepath.Join(notesDir, "note2.gpg")
	encryptNote(t, keyIDs, "Another note", notePath2)
	changed = UpdateAll(notesDir, cacheFile, keyIDs)

	if changed == 0 {
		t.Error("expected changes after adding note2")
	}
}

func TestUpdateSingle(t *testing.T) {
	_, keyIDs := setupGPG(t)
	notesDir := t.TempDir()
	cacheFile := filepath.Join(t.TempDir(), "notes.cache")

	// Create one encrypted note
	notePath := filepath.Join(notesDir, "note1.gpg")
	encryptNote(t, keyIDs, "Line 1", notePath)
	UpdateAll(notesDir, cacheFile, keyIDs)

	// Create a second note and update single
	notePath2 := filepath.Join(notesDir, "note2.gpg")
	encryptNote(t, keyIDs, "Line 2", notePath2)
	changed := UpdateSingle(notesDir, cacheFile, keyIDs, notePath2)

	if !changed {
		t.Error("expected change from UpdateSingle")
	}

	// Verify both notes exist in cache
	entries := DecryptAndLoad(cacheFile)

	if len(entries) != 2 {
		t.Errorf("expected 2 entries, got %d", len(entries))
	}
}

func TestUpdateAllSkipsWhenNoKeysExist(t *testing.T) {
	// Don't call setupGPG, so no keys are created
	notesDir := t.TempDir()
	cacheFile := filepath.Join(t.TempDir(), "notes.cache")

	// Create a dummy encrypted file (unrelated key)
	notePath := filepath.Join(notesDir, "note1.gpg")
	os.WriteFile(notePath, []byte("fake data"), 0600)

	// Attempt to run UpdateAll with a non-existent key
	changed := UpdateAll(notesDir, cacheFile, []string{"missing@example.com"})

	if changed != 0 {
		t.Errorf("expected 0 changes when no recipients exist, got %d", changed)
	}

	if _, err := os.Stat(cacheFile); err == nil {
		t.Error("expected cache file not to be created")
	}
}
