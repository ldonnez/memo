package main

import (
	"fmt"
	"memo/cache_builder"
	"os"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintf(os.Stderr, "Usage: %s <notes-dir> <cache-file> <key-ids> [file1 file2 ...]\n", os.Args[0])
		os.Exit(1)
	}

	notesDir := os.Args[1]
	cacheFile := os.Args[2]

	keyIDs := strings.Split(os.Args[3], ",")
	for i := range keyIDs {
		keyIDs[i] = strings.TrimSpace(keyIDs[i])
	}

	args := os.Args[4:]
	files := args

	start := time.Now()
	if len(files) > 0 {
		changed := cache_builder.UpdateManyFiles(notesDir, cacheFile, keyIDs, files)
		fmt.Printf("Cache updated (%d file(s) changed) in %.3fs\n", changed, time.Since(start).Seconds())
	} else {
		changed := cache_builder.UpdateAll(notesDir, cacheFile, keyIDs)
		fmt.Printf("Cache updated (%d file(s) changed) in %.3fs\n", changed, time.Since(start).Seconds())
	}
}
