package cache_builder

import (
	"crypto/md5"
	"fmt"
	"io"
	"os"
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

// Function variables for dependency injection in tests
var ProcessFileFn = processFile
var SaveIndexFn = saveIndex
var LoadIndexFn = loadIndex
var FindFilesFn = findFiles

func UpdateAll(notesDir, cacheFile, keyID string) int {
	oldEntries := LoadIndexFn(cacheFile)
	oldMap := make(map[string]Entry)
	for _, entry := range oldEntries {
		key := entry.Path + "|" + strconv.FormatInt(entry.Size, 10)
		oldMap[key] = entry
	}

	files := FindFilesFn(notesDir, ".gpg")
	var newEntries []Entry
	changed := 0
	currentFiles := make(map[string]bool)

	for _, file := range files {
		path := strings.TrimPrefix(file, notesDir+"/")
		currentFiles[path] = true

		size, hash := GetFileInfo(file)
		key := path + "|" + strconv.FormatInt(size, 10)

		if old, exists := oldMap[key]; exists && old.Hash == hash {
			for _, entry := range oldEntries {
				if entry.Path == path && entry.Size == size && entry.Hash == hash {
					newEntries = append(newEntries, entry)
				}
			}
		} else {
			entries := ProcessFileFn(file, path, size, hash)
			newEntries = append(newEntries, entries...)
			changed++
		}
	}

	for _, old := range oldEntries {
		if !currentFiles[old.Path] {
			changed++
			break
		}
	}

	if changed > 0 {
		SaveIndexFn(newEntries, cacheFile, keyID)
	}
	return changed
}

func UpdateSingle(notesDir, cacheFile, keyID, file string) bool {
	if !strings.HasSuffix(file, ".gpg") {
		return false
	}

	path := strings.TrimPrefix(file, notesDir+"/")
	size, hash := GetFileInfo(file)
	oldEntries := LoadIndexFn(cacheFile)

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

	entries := ProcessFileFn(file, path, size, hash)
	newEntries = append(newEntries, entries...)
	SaveIndexFn(newEntries, cacheFile, keyID)
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

func saveIndex(entries []Entry, cacheFile, keyID string) {
	sort.Slice(entries, func(i, j int) bool {
		if entries[i].Path == entries[j].Path {
			return entries[i].Content < entries[j].Content
		}
		return entries[i].Path < entries[j].Path
	})
	EncryptAndWrite(entries, cacheFile, keyID)
}

func loadIndex(cacheFile string) []Entry {
	return DecryptAndLoad(cacheFile)
}
