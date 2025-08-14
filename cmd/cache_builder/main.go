package main

import (
	"fmt"
	"memo/cache_builder"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintf(os.Stderr, "Usage: %s <notes-dir> <cache-file> <key-id> [file]\n", os.Args[0])
		os.Exit(1)
	}

	notesDir := os.Args[1]
	cacheFile := os.Args[2]
	keyIDs := strings.Split(os.Args[3], ",")
	singleFile := ""
	if len(os.Args) > 4 {
		singleFile = os.Args[4]
	}

	for i := range keyIDs {
		keyIDs[i] = strings.TrimSpace(keyIDs[i])
	}

	start := time.Now()
	if singleFile != "" {
		changed := cache_builder.UpdateSingle(notesDir, cacheFile, keyIDs, singleFile)
		if changed {
			fmt.Printf("Updated: %s (%.3fs)\n", filepath.Base(singleFile), time.Since(start).Seconds())
		}
	} else {
		count := cache_builder.UpdateAll(notesDir, cacheFile, keyIDs)
		fmt.Printf("Cache updated (%d files changed) in %.3fs\n", count, time.Since(start).Seconds())
	}
}
