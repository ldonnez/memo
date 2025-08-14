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
		path := strings.TrimPrefix(file, notesDir+"/")
		currentFiles[path] = true

		size, hash := GetFileInfo(file)
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
				entries := processFile(file, path, size, hash)
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

func UpdateSingle(notesDir string, cacheFile string, keyIDs []string, file string) bool {
	if !strings.HasSuffix(file, ".gpg") {
		return false
	}

	path := strings.TrimPrefix(file, notesDir+"/")
	size, hash := GetFileInfo(file)
	oldEntries := loadIndex(cacheFile)

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

	var newEntries []Entry
	for _, entry := range oldEntries {
		if entry.Path != path {
			newEntries = append(newEntries, entry)
		}
	}

	entries := processFile(file, path, size, hash)
	newEntries = append(newEntries, entries...)
	saveIndex(newEntries, cacheFile, keyIDs)
	return true
}

func FindFiles(dir, suffix string) []string {
	return findFiles(dir, suffix)
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

func GetFileInfo(file string) (int64, string) {
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
