package main

import (
	"fmt"
	"memo/cache_builder"
	"os"
	"strings"
)

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintf(os.Stderr, "Usage: %s <notes-dir> <cache-file> <key-ids> [file1 file2 ...]\n", os.Args[0])
		os.Exit(1)
	}

	notesDir := os.Args[1]
	cacheFile := os.Args[2]

	keyIDs := strings.Split(os.Args[3], ",")
	trimmedKeyIDs := []string{}

	for _, id := range keyIDs {
		trimmedID := strings.TrimSpace(id)
		if trimmedID != "" {
			trimmedKeyIDs = append(trimmedKeyIDs, trimmedID)
		}
	}

	args := os.Args[4:]
	files := args

	if len(files) > 0 {
		updatedFiles := cache_builder.UpdateManyFiles(notesDir, cacheFile, trimmedKeyIDs, files)
		printResult(updatedFiles)
		return
	}

	updatedFiles := cache_builder.UpdateAll(notesDir, cacheFile, trimmedKeyIDs)
	printResult(updatedFiles)
}

func printResult(updatedFiles []string) {
	if len(updatedFiles) > 0 {
		fmt.Println("Updated files in cache:")
		for _, f := range updatedFiles {
			fmt.Println("-", f)
		}
	} else {
		fmt.Println("No files updated in cache")
	}
}
