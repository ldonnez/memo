package cache_builder

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// setupTestGPG initializes a temporary GNUPGHOME and generates a test key.
// It returns the GNUPGHOME path and the key IDs (email addresses).
func setupTestGPG(t *testing.T) (gnupgHome string, keyIDs []string) {
	t.Helper()

	tmp := t.TempDir()
	t.Setenv("GNUPGHOME", tmp)

	// Ensure secure permissions to avoid gpg warnings
	if err := os.Chmod(tmp, 0700); err != nil {
		t.Fatalf("failed to chmod GNUPGHOME: %v", err)
	}

	// Minimal batch key specification
	keySpec := `
	Key-Type: EDDSA
	Key-Curve: Ed25519
	Subkey-Type: ECDH
	Subkey-Curve: Curve25519
	Name-Real: Test User
	Name-Email: test@example.com
	Expire-Date: 1d
	%no-protection
	%commit
	`
	specFile := filepath.Join(tmp, "keygen")
	if err := os.WriteFile(specFile, []byte(keySpec), 0600); err != nil {
		t.Fatal(err)
	}

	// Generate the key
	cmd := exec.Command("gpg", "--batch", "--gen-key", specFile)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("failed to generate test gpg key: %v\n%s", err, out)
	}

	// Kill agent on cleanup to avoid background processes hanging around
	t.Cleanup(func() {
		err := exec.Command("gpgconf", "--kill", "all").Run()

		if err != nil {
			t.Fatal(err)
		}
	})

	keys := []string{"test@example.com"}

	return tmp, keys
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
