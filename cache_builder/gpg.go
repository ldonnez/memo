package cache_builder

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

// Extract PGP blocks from a file
func extractPGPBlocks(file string) ([]string, error) {
	f, err := os.Open(file)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var blocks []string
	var buf bytes.Buffer
	inBlock := false

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "-----BEGIN PGP MESSAGE-----") {
			inBlock = true
			buf.Reset()
		}
		if inBlock {
			buf.WriteString(line + "\n")
		}
		if strings.HasPrefix(line, "-----END PGP MESSAGE-----") {
			inBlock = false
			blocks = append(blocks, buf.String())
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return blocks, nil
}

// Decrypt PGP block in-memory using gpg
func decryptPGPBlock(block string) (string, error) {
	cmd := exec.Command("gpg", "--quiet", "--batch", "--decrypt")
	cmd.Stdin = strings.NewReader(block)
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("decrypt failed: %w", err)
	}
	return string(out), nil
}

// Process a file with inline PGP messages
func processInlinePGPFile(file, path string, size int64, hash string) []Entry {
	blocks, err := extractPGPBlocks(file)
	if err != nil {
		fmt.Printf("Failed to extract PGP blocks: %s\n", file)
		return nil
	}

	var entries []Entry
	for _, block := range blocks {
		decrypted, err := decryptPGPBlock(block)
		if err != nil {
			fmt.Printf("Skipping undecryptable block in %s\n", file)
			continue
		}

		scanner := bufio.NewScanner(strings.NewReader(decrypted))
		lineNum := int64(1)
		for scanner.Scan() {
			entries = append(entries, Entry{
				Path:    path,
				LineNum: lineNum,
				Size:    size,
				Hash:    hash,
				Content: scanner.Text(),
			})
			lineNum++
		}
	}
	return entries
}

func DecryptAndLoad(cacheFile string) []Entry {
	cmd := exec.Command("gpg", "--quiet", "--decrypt", cacheFile)
	output, err := cmd.Output()
	if err != nil {
		return []Entry{}
	}
	var entries []Entry
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		parts := strings.SplitN(scanner.Text(), "|", 5)
		if len(parts) == 5 {
			lineNum, _ := strconv.ParseInt(parts[1], 10, 64)
			size, _ := strconv.ParseInt(parts[2], 10, 64)
			entries = append(entries, Entry{
				Path:    parts[0],
				LineNum: lineNum,
				Size:    size,
				Hash:    parts[3],
				Content: parts[4],
			})
		}
	}
	return entries
}

func EncryptAndWrite(entries []Entry, cacheFile string, keyIDs []string) {
	var content strings.Builder
	for _, entry := range entries {
		fmt.Fprintf(&content, "%s|%d|%d|%s|%s\n", entry.Path, entry.LineNum, entry.Size, entry.Hash, entry.Content)
	}

	args := []string{"--yes", "--batch", "--quiet"}
	for _, id := range keyIDs {
		args = append(args, "--recipient", id)
	}

	args = append(args, "--encrypt", "--output", cacheFile)

	cmd := exec.Command("gpg", args...)
	cmd.Stdin = strings.NewReader(content.String())
	cmd.Run()
}
