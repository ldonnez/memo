package cache_builder

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExtractPGPBlocks(t *testing.T) {
	tmp := t.TempDir()
	file := filepath.Join(tmp, "test.txt")

	content := `-----BEGIN PGP MESSAGE-----
abc
-----END PGP MESSAGE-----
`
	if err := os.WriteFile(file, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	blocks, err := extractPGPBlocks(file)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(blocks) != 1 {
		t.Fatalf("expected 1 block, got %d", len(blocks))
	}
	if !strings.Contains(blocks[0], "PGP MESSAGE") {
		t.Errorf("block missing header: %s", blocks[0])
	}
}

func TestEncryptDecryptRoundtrip(t *testing.T) {
	_, keyIDs := setupTestGPG(t)

	tmp := t.TempDir()
	cache := filepath.Join(tmp, "cache.gpg")

	entries := []Entry{
		{Path: "file.txt", LineNum: 1, Size: 123, Hash: "deadbeef", Content: "hello world"},
	}

	EncryptAndWrite(entries, cache, keyIDs)
	if _, err := os.Stat(cache); err != nil {
		t.Fatalf("cache file not written: %v", err)
	}

	loaded := DecryptAndLoad(cache)
	if len(loaded) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(loaded))
	}
	got := loaded[0]
	if got.Content != "hello world" || got.Path != "file.txt" {
		t.Errorf("wrong roundtrip result: %+v", got)
	}
}

func TestProcessInlinePGPFile(t *testing.T) {
	_, keyIDs := setupTestGPG(t)

	tmp := t.TempDir()
	file := filepath.Join(tmp, "inline.txt")

	embedEncryptedBlock(t, keyIDs, "Hello world\nSecond line", file)

	entries := processInlinePGPFile(file, "inline.txt", 42, "h")
	if len(entries) != 2 {
		t.Fatalf("expected 2 lines, got %d", len(entries))
	}
	if entries[0].LineNum != 1 || entries[1].LineNum != 2 {
		t.Errorf("line numbers not assigned correctly: %+v", entries)
	}
}
