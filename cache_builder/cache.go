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
	LineNum int64
	Size    int64
	Hash    string
	Content string
}

func UpdateAll(notesDir string, cacheFile string, keyIDs []string) []string {
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
		return nil
	}

	oldEntries := loadIndex(cacheFile)
	oldMap := loadOldEntriesMap(oldEntries)

	files := findFiles(notesDir, ".gpg")
	var newEntries []Entry
	updatedFiles := make(map[string]bool)
	currentFiles := make(map[string]bool)

	for _, file := range files {
		path, err := filepath.Rel(notesDir, file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Skipping file (cannot make relative): %s\n", file)
			continue
		}
		path = filepath.ToSlash(path)
		currentFiles[path] = true

		size, hash := getFileInfo(file)
		key := path + "|" + strconv.FormatInt(size, 10)

		if old, exists := oldMap[key]; exists && old.Hash == hash {
			newEntries = append(newEntries, old)
		} else {
			if canDecrypt(file) {
				entries := processInlinePGPFile(file, path, size, hash)
				newEntries = append(newEntries, entries...)
				updatedFiles[path] = true
			} else {
				fmt.Fprintf(os.Stderr, "Skipping undecryptable file: %s\n", file)
			}
		}
	}

	// Handle deleted files
	for _, old := range oldEntries {
		if !currentFiles[old.Path] {
			updatedFiles[old.Path] = true
		}
	}

	if len(updatedFiles) > 0 {
		saveIndex(newEntries, cacheFile, validKeys)
	}

	keys := make([]string, 0, len(updatedFiles))
	for k := range updatedFiles {
		keys = append(keys, k)
	}

	sort.Strings(keys)
	return keys
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

func UpdateManyFiles(notesDir string, cacheFile string, keyIDs []string, files []string) []string {
	oldEntries := loadIndex(cacheFile)
	oldMap := loadOldEntriesMap(oldEntries)

	newEntries := []Entry{}
	updatedFiles := make(map[string]bool)
	preservedPaths := make(map[string]bool)

	for _, file := range files {
		absFile, err := filepath.Abs(file)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Skipping file (cannot resolve abs): %s\n", file)
			continue
		}

		relPath, err := filepath.Rel(notesDir, absFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Skipping file (cannot make relative): %s\n", file)
			continue
		}
		path := filepath.ToSlash(relPath)
		preservedPaths[path] = true

		if skip, reason := shouldSkipFile(notesDir, absFile); skip {
			if reason == "missing or directory" {
				for _, old := range oldEntries {
					if old.Path == path {
						updatedFiles[path] = true
						break
					}
				}
				continue
			} else {
				fmt.Printf("Skipping %s: %s\n", reason, absFile)
				continue
			}
		}

		entries, fileChanged := processFileUpdate(absFile, path, oldMap)
		if fileChanged {
			updatedFiles[path] = true
		}
		newEntries = append(newEntries, entries...)
	}

	// Merge old entries that were not updated
	for _, old := range oldEntries {
		if !preservedPaths[old.Path] {
			fullPath := filepath.Join(notesDir, old.Path)
			if _, err := os.Stat(fullPath); os.IsNotExist(err) {
				continue
			}
			newEntries = append(newEntries, old)
		}
	}

	if len(updatedFiles) > 0 {
		saveIndex(newEntries, cacheFile, keyIDs)
	}

	keys := make([]string, 0, len(updatedFiles))
	for k := range updatedFiles {
		keys = append(keys, k)
	}

	sort.Strings(keys)
	return keys
}

func findFiles(dir, suffix string) []string {
	var files []string
	err := filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() && strings.HasSuffix(path, suffix) {
			files = append(files, path)
		}
		return nil
	})

	if err == nil {
		return files
	}

	return nil
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

	_, copyErr := io.Copy(h, f)
	if copyErr != nil {
		return 0, ""
	}

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
