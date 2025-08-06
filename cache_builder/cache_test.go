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

	keys := []string{"test@example.com"}
	return gnupgHome, keys
}

// Embed an encrypted message inside a text file (inline PGP)
func embedEncryptedBlock(t *testing.T, recipients []string, plaintext string, dest string) {
	t.Helper()
	args := []string{"--yes", "--batch", "--armor", "--encrypt"}
	for _, r := range recipients {
		args = append(args, "--recipient", r)
	}
	cmd := exec.Command("gpg", args...)
	cmd.Stdin = strings.NewReader(plaintext)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("failed to encrypt: %s\n%s", err, out)
	}
	// Write armored block into the file
	if err := os.WriteFile(dest, out, 0644); err != nil {
		t.Fatalf("failed to write file: %v", err)
	}
}

func TestUpdateAllWithInlinePGP(t *testing.T) {
	_, keyIDs := setupGPG(t)
	notesDir := t.TempDir()
	cacheFile := filepath.Join(t.TempDir(), "notes.cache")

	note1 := filepath.Join(notesDir, "note1.txt.gpg")
	embedEncryptedBlock(t, keyIDs, "Hello world\nSecond line", note1)

	changed := UpdateAll(notesDir, cacheFile, keyIDs)
	if changed == 0 {
		t.Fatal("expected changes, got 0")
	}

	entries := DecryptAndLoad(cacheFile)
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if entries[0].Content != "Hello world" || entries[1].Content != "Second line" {
		t.Errorf("unexpected cache content: %+v", entries)
	}
	if entries[0].LineNum != 1 {
		t.Errorf("unexpected linenumber: %+v", entries)
	}
	if entries[1].LineNum != 2 {
		t.Errorf("unexpected linenumber: %+v", entries)
	}

	// No change second run
	changed = UpdateAll(notesDir, cacheFile, keyIDs)
	if changed != 0 {
		t.Errorf("expected 0 changes on second run, got %d", changed)
	}
}

func TestUpdateManyFilesWithInlinePGP(t *testing.T) {
	_, keyIDs := setupGPG(t)
	notesDir := t.TempDir()
	cacheFile := filepath.Join(t.TempDir(), "notes.cache")

	// Create multiple inline PGP files
	note1 := filepath.Join(notesDir, "note1.txt.gpg")
	note2 := filepath.Join(notesDir, "note2.txt.gpg")
	note3 := filepath.Join(notesDir, "note3.txt.gpg")

	embedEncryptedBlock(t, keyIDs, "Line 1", note1)
	UpdateAll(notesDir, cacheFile, keyIDs)

	// Remove note1 from disk
	os.Remove(note1)

	embedEncryptedBlock(t, keyIDs, "Line 2", note2)
	embedEncryptedBlock(t, keyIDs, "Line 3", note3)

	files := []string{note1, note2, note3}
	changed := UpdateManyFiles(notesDir, cacheFile, keyIDs, files)

	if changed != 3 {
		t.Errorf("expected 3 changes from UpdateManyFiles, got %d", changed)
	}

	entries := DecryptAndLoad(cacheFile)
	if len(entries) != 2 {
		t.Errorf("expected 2 entries, got %d", len(entries))
	}
}

func TestUpdateAllRecursive(t *testing.T) {
	_, keyIDs := setupGPG(t)

	notesDir := t.TempDir()
	cacheFile := filepath.Join(t.TempDir(), "notes.cache")

	// Make a subdirectory inside notesDir
	subDir := filepath.Join(notesDir, "nested")
	if err := os.Mkdir(subDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Create encrypted notes in both root and subdir
	note1 := filepath.Join(notesDir, "root.gpg")
	note2 := filepath.Join(subDir, "nested.gpg")

	embedEncryptedBlock(t, keyIDs, "Root note line1\nRoot note line2", note1)
	embedEncryptedBlock(t, keyIDs, "Nested note line1", note2)

	changed := UpdateAll(notesDir, cacheFile, keyIDs)
	if changed == 0 {
		t.Fatal("expected changes when adding root + nested note, got 0")
	}

	entries := DecryptAndLoad(cacheFile)

	// We expect 3 lines total (2 from root, 1 from nested)
	if len(entries) != 3 {
		t.Fatalf("expected 3 entries, got %d", len(entries))
	}

	// Check that relative paths are preserved correctly
	paths := []string{entries[0].Path, entries[1].Path, entries[2].Path}
	foundRoot, foundNested := false, false
	for _, p := range paths {
		if strings.HasPrefix(p, "root.gpg") {
			foundRoot = true
		}
		if strings.HasPrefix(p, "nested/nested.gpg") {
			foundNested = true
		}
	}
	if !foundRoot {
		t.Errorf("expected root.gpg entry, got %+v", paths)
	}
	if !foundNested {
		t.Errorf("expected nested/nested.gpg entry, got %+v", paths)
	}
}

func TestCanDecryptAndMissingKey(t *testing.T) {
	gnupgHome, keyIDs := setupGPG(t)
	os.Setenv("GNUPGHOME", gnupgHome)

	tmpDir := t.TempDir()
	note := filepath.Join(tmpDir, "note.txt.gpg")
	embedEncryptedBlock(t, keyIDs, "Secret line", note)

	if !canDecrypt(note) {
		t.Error("expected canDecrypt to return true")
	}

	// Now test with non-existent recipient
	unreadable := filepath.Join(tmpDir, "bad.txt.gpg")
	if err := os.WriteFile(unreadable, []byte("-----BEGIN PGP MESSAGE-----\n...\n-----END PGP MESSAGE-----"), 0644); err != nil {
		t.Fatal(err)
	}
	if canDecrypt(unreadable) {
		t.Error("expected canDecrypt to return false for non-decryptable content")
	}
}
