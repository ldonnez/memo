package main

import (
	"bufio"
	"crypto/md5"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Entry struct {
	Path    string
	Size    int64
	Hash    string
	Content string
}

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintf(os.Stderr, "Usage: %s <notes-dir> <cache-file> <key-id> [file]\n", os.Args[0])
		os.Exit(1)
	}

	notesDir := os.Args[1]
	cacheFile := os.Args[2]
	keyID := os.Args[3]
	singleFile := ""

	if len(os.Args) > 4 {
		singleFile = os.Args[4]
	}

	start := time.Now()

	if singleFile != "" {
		changed := updateSingle(notesDir, cacheFile, keyID, singleFile)
		if changed {
			fmt.Printf("Updated: %s (%.3fs)\n", filepath.Base(singleFile), time.Since(start).Seconds())
		}
	} else {
		count := updateAll(notesDir, cacheFile, keyID)
		fmt.Printf("Cache updated (%d files changed) in %.3fs\n", count, time.Since(start).Seconds())
	}
}

func updateAll(notesDir, cacheFile, keyID string) int {
	// Load old index into map for O(1) lookup
	oldEntries := loadIndex(cacheFile)
	oldMap := make(map[string]Entry)
	for _, entry := range oldEntries {
		key := entry.Path + "|" + strconv.FormatInt(entry.Size, 10)
		oldMap[key] = entry
	}

	// Find all .gpg files
	files := findFiles(notesDir, ".gpg")

	var newEntries []Entry
	changed := 0

	// Check existing files
	currentFiles := make(map[string]bool)
	for _, file := range files {
		path := strings.TrimPrefix(file, notesDir+"/")
		currentFiles[path] = true

		size, hash := getFileInfo(file)
		key := path + "|" + strconv.FormatInt(size, 10)

		if old, exists := oldMap[key]; exists && old.Hash == hash {
			// Unchanged - copy old entries
			for _, entry := range oldEntries {
				if entry.Path == path && entry.Size == size && entry.Hash == hash {
					newEntries = append(newEntries, entry)
				}
			}
		} else {
			// Changed or new - process file
			entries := processFile(file, path, size, hash)
			newEntries = append(newEntries, entries...)
			changed++
		}
	}

	// Check for deleted files
	for _, old := range oldEntries {
		if !currentFiles[old.Path] {
			changed++
			break // Just need to know something changed
		}
	}

	if changed > 0 {
		saveIndex(newEntries, cacheFile, keyID)
	}

	return changed
}

func updateSingle(notesDir, cacheFile, keyID, file string) bool {
	if !strings.HasSuffix(file, ".gpg") {
		fmt.Fprintf(os.Stderr, "Error: File must end with .gpg\n")
		os.Exit(1)
	}

	path := strings.TrimPrefix(file, notesDir+"/")
	size, hash := getFileInfo(file)

	// Load old index
	oldEntries := loadIndex(cacheFile)

	// Check if changed
	unchanged := false
	for _, old := range oldEntries {
		if old.Path == path && old.Size == size && old.Hash == hash {
			unchanged = true
			break
		}
	}

	if unchanged {
		return false
	}

	// Remove old entries for this file
	var newEntries []Entry
	for _, entry := range oldEntries {
		if entry.Path != path {
			newEntries = append(newEntries, entry)
		}
	}

	// Add new entries
	entries := processFile(file, path, size, hash)
	newEntries = append(newEntries, entries...)

	saveIndex(newEntries, cacheFile, keyID)
	return true
}

func findFiles(dir, suffix string) []string {
	var files []string
	filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() && strings.HasSuffix(path, suffix) {
			files = append(files, path)
		}
		return nil
	})
	return files
}

func getFileInfo(file string) (int64, string) {
	stat, err := os.Stat(file)
	if err != nil {
		return 0, ""
	}

	f, err := os.Open(file)
	if err != nil {
		return 0, ""
	}
	defer f.Close()

	h := md5.New()
	io.Copy(h, f)

	return stat.Size(), fmt.Sprintf("%x", h.Sum(nil))
}

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

func loadIndex(cacheFile string) []Entry {
	if _, err := os.Stat(cacheFile); os.IsNotExist(err) {
		return []Entry{}
	}

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

func saveIndex(entries []Entry, cacheFile, keyID string) {
	// Sort for consistent output
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Path == entries[j].Path {
			return entries[i].Content < entries[j].Content
		}
		return entries[i].Path < entries[j].Path
	})

	var content strings.Builder
	for _, entry := range entries {
		fmt.Fprintf(&content, "%s|%d|%s|%s\n", entry.Path, entry.Size, entry.Hash, entry.Content)
	}

	cmd := exec.Command("gpg", "--yes", "--batch", "--quiet", "--recipient", keyID, "--encrypt", "--output", cacheFile)
	cmd.Stdin = strings.NewReader(content.String())
	cmd.Run()
}
