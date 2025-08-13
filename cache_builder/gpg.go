package cache_builder

import (
	"bufio"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

func processFile(file, path string, size int64, hash string) []Entry {
	cmd := exec.Command("gpg", "--quiet", "--decrypt", file)
	output, err := cmd.Output()
	if err != nil {
		return []Entry{}
	}
	var entries []Entry
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		entries = append(entries, Entry{
			Path:    path,
			Size:    size,
			Hash:    hash,
			Content: scanner.Text(),
		})
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
		parts := strings.SplitN(scanner.Text(), "|", 4)
		if len(parts) == 4 {
			size, _ := strconv.ParseInt(parts[1], 10, 64)
			entries = append(entries, Entry{
				Path:    parts[0],
				Size:    size,
				Hash:    parts[2],
				Content: parts[3],
			})
		}
	}
	return entries
}

func EncryptAndWrite(entries []Entry, cacheFile, keyID string) {
	var content strings.Builder
	for _, entry := range entries {
		fmt.Fprintf(&content, "%s|%d|%s|%s\n", entry.Path, entry.Size, entry.Hash, entry.Content)
	}
	cmd := exec.Command("gpg", "--yes", "--batch", "--quiet", "--recipient", keyID, "--encrypt", "--output", cacheFile)
	cmd.Stdin = strings.NewReader(content.String())
	cmd.Run()
}
