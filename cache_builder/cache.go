package cache_builder

import (
	"crypto/md5"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type Entry struct {
	Path    string
	Size    int64
	Hash    string
	Content string
}

func UpdateAll(notesDir string, cacheFile string, keyIDs []string) int {
	// Filter only existing keys
	validKeys := []string{}
	for _, key := range keyIDs {
		if gpgKeyExists(key) {
			validKeys = append(validKeys, key)
		} else {
			fmt.Fprintf(os.Stderr, "Skipping missing recipient: %s\n", key)
		}
	}

	if len(validKeys) == 0 {
		fmt.Fprintln(os.Stderr, "No valid recipients found — skipping cache build.")
		return 0
	}

	oldEntries := loadIndex(cacheFile)
	oldMap := make(map[string]Entry)
	for _, entry := range oldEntries {
		key := entry.Path + "|" + strconv.FormatInt(entry.Size, 10)
		oldMap[key] = entry
	}

	files := findFiles(notesDir, ".gpg")
	var newEntries []Entry
	changed := 0
	currentFiles := make(map[string]bool)

	for _, file := range files {
		relPath, err := filepath.Rel(notesDir, file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Skipping file (cannot make relative): %s\n", file)
			continue
		}
		path := filepath.ToSlash(relPath)
		currentFiles[path] = true

		size, hash := getFileInfo(file)
		key := path + "|" + strconv.FormatInt(size, 10)

		if old, exists := oldMap[key]; exists && old.Hash == hash {
			// File unchanged — reuse old entry
			for _, entry := range oldEntries {
				if entry.Path == path && entry.Size == size && entry.Hash == hash {
					newEntries = append(newEntries, entry)
				}
			}
		} else {
			if canDecrypt(file) { // <-- new check before decrypting
				entries := processInlinePGPFile(file, path, size, hash)
				newEntries = append(newEntries, entries...)
				changed++
			} else {
				fmt.Fprintf(os.Stderr, "Skipping undecryptable file: %s\n", file)
			}
		}
	}

	// Detect deleted files
	for _, old := range oldEntries {
		if !currentFiles[old.Path] {
			changed++
			break
		}
	}

	if changed > 0 {
		saveIndex(newEntries, cacheFile, validKeys) // use only valid keys
	}
	return changed
}

func gpgKeyExists(keyID string) bool {
	cmd := exec.Command("gpg", "--list-keys", keyID)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run() == nil
}

func canDecrypt(file string) bool {
	cmd := exec.Command("gpg", "--list-packets", file)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run() == nil
}

func loadOldEntriesMap(oldEntries []Entry) map[string]Entry {
	m := make(map[string]Entry)
	for _, e := range oldEntries {
		key := e.Path + "|" + strconv.FormatInt(e.Size, 10)
		m[key] = e
	}
	return m
}

func shouldSkipFile(notesDir, file string) (bool, string) {
	if !strings.HasSuffix(file, ".gpg") {
		return true, "non-gpg file"
	}
	if !isInsideDir(notesDir, file) {
		return true, "file outside notesDir"
	}
	info, err := os.Stat(file)
	if err != nil || info.IsDir() {
		return true, "missing or directory"
	}
	return false, ""
}

func processFileUpdate(file string, path string, oldMap map[string]Entry) ([]Entry, bool) {
	size, hash := getFileInfo(file)
	key := path + "|" + strconv.FormatInt(size, 10)

	if old, exists := oldMap[key]; exists && old.Hash == hash {
		return []Entry{old}, false
	}
	if canDecrypt(file) {
		entries := processInlinePGPFile(file, path, size, hash)
		return entries, true
	}
	fmt.Printf("Skipping undecryptable file: %s\n", file)
	return nil, false
}

func mergeOldEntries(notesDir string, oldEntries []Entry, preservedPaths map[string]bool) []Entry {
	newEntries := []Entry{}
	for _, old := range oldEntries {
		if preservedPaths[old.Path] {
			continue
		}
		fullPath := filepath.Join(notesDir, old.Path)
		info, err := os.Stat(fullPath)
		if err != nil || info.IsDir() {
			// missing/deleted → handled elsewhere
			continue
		}
		newEntries = append(newEntries, old)
	}
	return newEntries
}

func UpdateManyFiles(notesDir string, cacheFile string, keyIDs []string, files []string) int {
	oldEntries := loadIndex(cacheFile)
	oldMap := loadOldEntriesMap(oldEntries)

	newEntries := []Entry{}
	changed := 0
	preservedPaths := make(map[string]bool)

	for _, file := range files {
		relPath, err := filepath.Rel(notesDir, file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Skipping file (cannot make relative): %s\n", file)
			continue
		}
		path := filepath.ToSlash(relPath)
		preservedPaths[path] = true

		if skip, reason := shouldSkipFile(notesDir, file); skip {
			if reason == "missing or directory" {
				foundInCache := false
				for _, old := range oldEntries {
					if old.Path == path {
						changed++
						foundInCache = true
						break
					}
				}
				if !foundInCache {
					continue // missing file not in cache → ignore
				}
			} else {
				fmt.Printf("Skipping %s: %s\n", reason, file)
				continue
			}
		}

		entries, fileChanged := processFileUpdate(file, path, oldMap)
		if fileChanged {
			changed++
		}
		newEntries = append(newEntries, entries...)
	}

	// Merge old entries that were not updated
	newEntries = append(newEntries, mergeOldEntries(notesDir, oldEntries, preservedPaths)...)

	if changed > 0 {
		saveIndex(newEntries, cacheFile, keyIDs)
	}

	return changed
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

// Checks if a GPG public key exists in the keyring
func keyExists(id string) bool {
	cmd := exec.Command("gpg", "--list-keys", id)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run() == nil
}

func saveIndex(entries []Entry, cacheFile string, keyIDs []string) {
	// Filter valid recipients
	var validKeys []string
	for _, id := range keyIDs {
		if keyExists(id) {
			validKeys = append(validKeys, id)
		} else {
			fmt.Printf("Skipping missing recipient: %s\n", id)
		}
	}

	// No valid recipients? Skip cache creation.
	if len(validKeys) == 0 {
		fmt.Println("No valid recipients found — skipping cache build")
		return
	}

	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Path == entries[j].Path {
			return entries[i].Content < entries[j].Content
		}
		return entries[i].Path < entries[j].Path
	})
	EncryptAndWrite(entries, cacheFile, keyIDs)
}

func loadIndex(cacheFile string) []Entry {
	if _, err := os.Stat(cacheFile); err != nil {
		return nil
	}

	return DecryptAndLoad(cacheFile)
}

func isInsideDir(baseDir, targetPath string) bool {
	absBase, err := filepath.Abs(baseDir)
	if err != nil {
		return false
	}
	absTarget, err := filepath.Abs(targetPath)
	if err != nil {
		return false
	}

	rel, err := filepath.Rel(absBase, absTarget)
	if err != nil {
		return false
	}

	// If rel starts with "..", the target is outside of baseDir.
	return !strings.HasPrefix(rel, "..")
}
