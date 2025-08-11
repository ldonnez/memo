#!/usr/bin/env bash

set -euo pipefail

# TODO: Add IGNORE_PATTERNS in config file?
# TODO: Add tests for this
IGNORE_PATTERNS=(
  "*.bak"
  "*.tmp"
  ".git"
  ".DS_Store"
  "README.md"
)

# Helpers
dir_exists() {
  [[ -d "$1" ]]
}

file_exists() {
  local filepath="$1"
  [[ -f "$filepath" ]]
}

file_is_gpg() {
  local filepath="$1"
  [[ "$filepath" == *".gpg" ]]
}

file_content_is_equal() {
  local file1_hash
  file1_hash=$(get_hash "$1") || return 1

  local file2_hash
  file2_hash=$(get_hash "$2") || return 1

  if [[ "$file1_hash" == "$file2_hash" ]]; then
    return 0
  fi

  return 1
}

is_file_older_than() {
  local file1="$1"
  local file2="$2"

  [[ "$file1" -ot "$file2" ]]
}

# TODO: Add tests for this
is_ignored_path() {
  local path="$1"
  for ignore in "${IGNORE_PATTERNS[@]}"; do
    [[ "$path" == *"/$ignore/"* || "$path" == *"/$ignore/"*/* ]] && return 0
  done
  return 1
}

filename_is_date() {
  local filename="$1"

  # Strip path and isolate base name
  filename="${filename##*/}"

  # Extract just the name before the first extension
  # Example: 2025-08-05.md.gpg → 2025-08-05
  local base="${filename%%.*}"

  # Check if base name matches YYYY-MM-DD format
  if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    return 0
  else
    return 1
  fi
}

# TODO: Add tests for this
load_config() {
  local config_file="$1"

  # Set defaults
  : "${KEY_ID:=you@example.com}"
  : "${NOTES_DIR:=$HOME/notes}"
  : "${DAILY_NOTES_DIR:=$NOTES_DIR/dailies}"
  : "${EDITOR_CMD:=${EDITOR:-nano}}"
  : "${CACHE_DIR:=$HOME/.cache/memo}"
  : "${CACHE_FILE:=$CACHE_DIR/notes.cache}"

  if file_exists "$config_file"; then
    # shellcheck source=/dev/null
    source "$config_file"
  else
    echo "⚠️ Config file not found: $config_file" >&2
  fi
}

# TODO: Add tests for this
# Validate KEY_ID exists in GPG keyring
gpg_key_exists() {
  local key_id="$1"

  if ! gpg --list-keys "$key_id" &>/dev/null; then
    echo "GPG key not found for KEY_ID: $KEY_ID" >&2
    exit 1
  fi
}

# TODO: Add tests for this
create_dirs() {
  # Create directories if not exist
  mkdir -p "$NOTES_DIR"
  mkdir -p "$DAILY_NOTES_DIR"
  mkdir -p "$CACHE_DIR"
  chmod 700 "$CACHE_DIR" # Ensure only current user can write to .cache dir.
}

determine_filename() {
  local input="$1"

  if [[ -z "$input" || "$input" == "today" ]]; then
    echo "$(date +%F).md"
    return 0
  fi

  if [[ "$input" == "yesterday" ]]; then
    echo "$(date -d "yesterday" +%F 2>/dev/null || date -v-1d +%F).md"
    return 0
  fi

  if [[ "$input" == "tomorrow" ]]; then
    echo "$(date -d "tomorrow" +%F 2>/dev/null || date -v+1d +%F).md"
    return 0
  fi

  if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$input.md"
    return 0
  fi

  echo "$input"
  return 0
}

find_note() {
  local filename="$1"
  local note_path

  # Use find to search for the file recursively.
  # It's important to use -print0 and xargs -0 for filenames with spaces.
  # The -quit flag is a GNU find extension to stop after the first match.
  # We use a subshell to capture the output without affecting the main script.
  if [[ "$(uname -s)" == "Linux" ]]; then
    note_path=$(find "$NOTES_DIR" -type f -name "$filename" -print0 -quit | xargs -0 -I {} echo "{}")
  else
    # On macOS (BSD find), we can't use -quit with -print0, so we use head
    note_path=$(find "$NOTES_DIR" -type f -name "$filename" -print0 | head -z -n 1 | xargs -0 -I {} echo "{}")
  fi

  # Return the full path of the found file
  if [[ -n "$note_path" ]]; then
    echo "$note_path"
    return 0
  else
    return 1
  fi
}

get_filepath() {
  local input="$1"
  local filename
  filename=$(determine_filename "$input")

  local filepath

  if filename_is_date "$filename"; then
    filepath="$DAILY_NOTES_DIR/$filename"
  elif [[ "$PWD" == "$NOTES_DIR"* ]]; then
    filepath="$PWD/$input"
  elif file_exists "$filename" && file_is_gpg "$filename"; then
    filepath="$filename"
  else
    filepath="$NOTES_DIR/$filename"
  fi

  dirpath=$(dirname "$filepath")
  mkdir -p "$dirpath"

  echo "$filepath"
}

gpg_encrypt() {
  # Sets output_path to input_path when output_path is not given
  local input_path="$1" output_path="${2-$1}"

  gpg --quiet --yes --encrypt -r "$KEY_ID" -o "$output_path" "$input_path"
  echo "Encrypted: $output_path"
}

gpg_decrypt() {
  local input_path="$1" output_path="$2"

  gpg --quiet --decrypt "$input_path" >"$output_path" || {
    echo "Failed to decrypt $input_path"
    return 1
  }
}

make_tempfile() {
  local encrypted_file="$1"
  local relname="${encrypted_file##*/}" # remove path /path/to/2025-01-01.md.gpg -> 2025-01-01.md.gpg
  local base="${relname%.gpg}"          # remove .gpg extension 2025-01-01.md.gpg → 2025-01-01.md

  local tmpdir
  if dir_exists /dev/shm; then
    tmpdir="/dev/shm"
  else
    tmpdir=$(mktemp -d 2>/dev/null || echo "/tmp")
  fi

  local tmpfile="$tmpdir/memo-${base}"
  echo "$tmpfile"
}

decrypt_file_to_temp() {
  local encfile="$1"
  local basename="${encfile##*/}"
  local tmpfile
  tmpfile=$(make_tempfile "$basename")

  if gpg_decrypt "$encfile" "$tmpfile"; then
    echo "$tmpfile"
  else
    return 1
  fi
}

# Portable mtime getter
file_mtime() {
  local file="$1"
  if stat --version >/dev/null 2>&1; then
    stat -c %Y "$file"
  else
    stat -f %m "$file"
  fi
}

update_cache_file() {
  local encfile="$1"
  local relpath
  relpath=$(realpath --relative-to="$NOTES_DIR" "$encfile")
  local decfile="$CACHE_DIR/${relpath%.gpg}"
  mkdir -p "$(dirname "$decfile")"
  gpg_decrypt "$encfile" "$decfile" || rm -f "$decfile"
}

# TODO: Add tests for this
# TODO: Can't we make this simpler by not asking for it. It can be annoying.
save_file() {
  local decrypted_file="$1"
  local encrypted_file="$2"

  # If the encrypted file doesn't exist, skip comparison and prompt for encryption
  if ! file_exists "$encrypted_file"; then
    encrypt_file "$decrypted_file" "$encrypted_file"
    update_note_index "$encrypted_file"
    return
  fi

  if should_encrypt_file "$decrypted_file" "$encrypted_file"; then
    encrypt_file "$decrypted_file" "$encrypted_file"
    update_note_index "$encrypted_file"
  fi
}

strip_path() {
  local filepath="$1"
  echo "${filepath##*/}"
}

strip_extensions() {
  local filename="$1"
  while [[ "$filename" == *.* ]]; do
    filename="${filename%.*}"
  done
  echo "$filename"
}

should_encrypt_file() {
  # Sets encrypted_file to plaintext when encrypted_file is not given
  local plaintext="$1" encrypted_file="${2-$1}"

  if ! file_exists "$encrypted_file"; then
    return 0
  fi
  local tmp_file
  tmp_file=$(decrypt_file_to_temp "$encrypted_file")

  if file_content_is_equal "$plaintext" "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  else
    rm -f "$tmp_file"
    return 0
  fi
}

# TODO: Add tests for this
encrypt_file() {
  local input_file="$1" output_file="$2" dry="${3-0}"

  if [[ "$dry" -eq 1 ]]; then
    echo "Would encrypt: $input_file → $output_file.gpg"
    echo "Would delete: $input_file"
  else
    gpg_encrypt "$input_file" "$output_file"
    rm -f "$input_file"
  fi
}

is_in_notes_dir() {
  local fullpath="$1"
  local notes_dir="$NOTES_DIR"

  # Remove trailing slash from NOTES_DIR if it exists, for consistent comparison
  notes_dir=${notes_dir%/}

  # Use a simple string comparison to check if the path starts with the notes directory.
  if [[ "$fullpath" == "$notes_dir"* ]]; then
    return 0
  else
    return 1
  fi
}

get_target_filepath() {
  local input="$1"
  local fullpath

  if [[ -z "$input" ]]; then
    # No argument provided, create a new file with current date (YYYY-MM-DD) as filename.
    get_filepath ""
    return
  fi

  if file_exists "$input"; then
    fullpath=$(readlink -f "$input")
    if is_in_notes_dir "$fullpath" && file_is_gpg "$input"; then
      echo "$fullpath"
      return
    else
      echo "Error: File is not a valid gpg memo in the notes directory." >&2
      return 1
    fi
  else
    # File doesn't exist, generate a new one.
    get_filepath "$input"
    return
  fi
}

make_or_edit_file() {
  local filepath="$1"

  local tmpfile
  tmpfile=$(make_tempfile "${filepath##*/}")

  if file_exists "$filepath.gpg"; then
    gpg_decrypt "$filepath.gpg" "$tmpfile"
  elif file_is_gpg "$filepath"; then
    gpg_decrypt "$filepath" "$tmpfile"
  else
    local header
    header=$(strip_extensions "$(strip_path "$filepath")")
    echo "# $header" >"$tmpfile"
    echo "" >>"$tmpfile"
  fi

  echo "$tmpfile"
}

update_memo_index_entry() {
  local gpg_filepath="$1"
  local relative_path=${gpg_filepath#"$NOTES_DIR/"}

  # Decrypt the old cache to a temporary file
  local temp_old_index
  temp_old_index=$(mktemp)
  if [[ -f "$CACHE_FILE" ]]; then
    gpg --quiet --decrypt "$CACHE_FILE" >"$temp_old_index"
  fi

  # Create a new temporary index file to store the updated index
  local temp_new_index
  temp_new_index=$(mktemp)

  # Copy all entries from the old cache except the one we are updating
  if [[ -f "$temp_old_index" ]]; then
    awk -F'|' -v path="$relative_path" '$1 != path' "$temp_old_index" >"$temp_new_index"
  fi

  # Get the new content and hash of the updated file
  local decrypted_content
  decrypted_content=$(gpg --quiet --decrypt "$gpg_filepath")

  local new_hash
  new_hash=$(get_hash "$gpg_filepath")

  # Add the new entry to the temporary index
  echo "$decrypted_content" | while read -r line; do
    printf "%s|%s|%s\n" "$relative_path" "$new_hash" "$line" >>"$temp_new_index"
  done

  # Re-encrypt the new index and replace the old cache
  gpg --quiet --yes --recipient "$KEY_ID" --encrypt --output "$CACHE_FILE" "$temp_new_index"

  # Clean up temporary files
  rm "$temp_old_index" "$temp_new_index"

  echo "Cache for '$relative_path' has been updated."
}

# Commands
# TODO: Add tests for this
edit_memo() {
  local input="$1"

  local filepath
  filepath=$(get_target_filepath "$1") || return 1

  local tmpfile
  tmpfile=$(make_or_edit_file "$filepath")

  "$EDITOR_CMD" "$tmpfile"

  if file_is_gpg "$filepath"; then
    save_file "$tmpfile" "$filepath"
  else
    save_file "$tmpfile" "$filepath.gpg"
  fi

  shred -u "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
}

# TODO: Add tests for this
unlock() {
  local target="$1"
  if [[ -z "$target" ]]; then
    echo "Usage: memo unlock <filename.gpg | all>"
    return 1
  fi

  if [[ "$target" == "all" ]]; then
    find "$NOTES_DIR" -type f -name "*.gpg" | while read -r file; do
      local plaintext="${file%.gpg}"
      [[ -f "$plaintext" ]] && echo "Skipping: $plaintext" && continue
      gpg_decrypt "$file" "$plaintext" && echo "Decrypted: $plaintext"
    done
  else
    local file
    file=$(find "$NOTES_DIR" -type f -name "$target" | head -n 1)
    [[ -z "$file" ]] && echo "File not found: $target" && return 1
    local plaintext="${file%.gpg}"
    [[ -f "$plaintext" ]] && echo "Already exists: $plaintext" && return 1
    gpg_decrypt "$file" "$plaintext" && echo "Decrypted: $plaintext"
  fi
  echo "Run 'memo lock all' to re-encrypt"
}

# TODO: Add tests for this
lock() {
  local dry=0 target exclude_patterns=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run) dry=1 ;;
    --exclude)
      exclude_patterns+=("$2")
      shift
      ;;
    *) target="$1" ;;
    esac
    shift
  done

  if [[ -z "$target" ]]; then
    echo "Usage: memo lock <filename | all> [--dry-run] [--exclude pattern]"
    return 1
  fi

  if [[ "$target" == "all" ]]; then
    find "$NOTES_DIR" -type f ! -name "*.gpg" | while read -r file; do
      is_ignored_path "$file" && continue

      for pattern in "${exclude_patterns[@]}"; do
        [[ $(basename "$file") == "$pattern" ]] && echo "Skipping: $file" && continue 2
      done
      local encfile="$file.gpg"
      should_encrypt_file "$file" "$encfile" && encrypt_file "$file" "$file" "$dry"
    done
  else
    local file
    file=$(find "$NOTES_DIR" -type f -name "$target" | head -n 1)
    [[ -z "$file" ]] && echo "Not found: $target" && return 1
    local encfile="$file.gpg"
    should_encrypt_file "$file" "$encfile" && encrypt_file "$file" "$file" "$dry"
  fi
}

# TODO: Add tests for this
search_memo_filenames() {
  local result
  result=$(find "$NOTES_DIR" -type f -name "*.gpg" | fzf --preview "gpg --quiet --decrypt {} 2>/dev/null | head -100")
  [[ -z "$result" ]] && return
  local tmpfile
  tmpfile=$(decrypt_file_to_temp "$result") || return
  "$EDITOR_CMD" "$tmpfile"
  save_file "$tmpfile" "$result"
}

memo_test() {
  echo "NOTHING TO TEST"
}

# TODO: Add tests for this
memo_remove() {
  local input="$1"
  [[ -z "$input" ]] && echo "No memo filename provided." && return 1

  # Normalize filename: append .gpg if missing
  [[ "$input" != *.gpg ]] && input="${input}.gpg"

  local filepath="$NOTES_DIR/$input"
  if [[ ! -f "$filepath" ]]; then
    echo "Memo not found: $filepath"
    return 1
  fi

  read -rp "🗑️  Are you sure you want to delete '$filepath'? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Deletion cancelled."
    return 1
  fi

  # Delete memo
  rm -f "$filepath"
  echo "Removed: $filepath"

  # Remove from cache if present
  if [[ -n "$CACHE_DIR" ]]; then
    local relpath decfile
    relpath=$(realpath --relative-to="$NOTES_DIR" "$filepath")
    decfile="$CACHE_DIR/${relpath%.gpg}"
    if [[ -f "$decfile" ]]; then
      rm -f "$decfile"
      echo "Cache cleaned: $decfile"
    fi
  fi
}

# Cross-platform function to get file modification time
function get_mtime() {
  local filename="$1"
  local os_name
  os_name=$(uname -s)

  if [[ "$os_name" == "Linux" ]]; then
    # GNU stat on Linux
    stat -c %Y "$filename"
  elif [[ "$os_name" == "Darwin" ]]; then
    # BSD stat on macOS
    stat -f "%m" "$filename"
  else
    # Fallback for other systems
    echo "Unknown OS"
  fi
}

# --- Helpers ---
get_size() {
  local filename="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    stat -f %z "$filename"
  else
    stat -c %s "$filename"
  fi
}

get_hash() {
  local filename="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    md5 -q "$filename"
  else
    md5sum "$filename" | awk '{print $1}'
  fi
}

hash_path() {
  local str="$1"
  local hash=0 i ch
  for ((i = 0; i < ${#str}; i++)); do
    ch=$(printf "%d" "'${str:i:1}")
    hash=$(((hash * 31 + ch) % HASH_BUCKETS))
  done
  echo "$hash"
}

# --- Main ---
# Incrementally update note index - optimized for single file changes
update_note_index() {
  local target_file="${1-""}" # Optional: specific file to update
  local start_time
  start_time=$(date +%s)

  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf '"$tmpdir"'' EXIT

  local temp_new_index="$tmpdir/new_index"
  local old_index_file="$tmpdir/old_index"

  # Decrypt old index if it exists, otherwise start fresh
  if [[ -f "$CACHE_FILE" ]]; then
    gpg --quiet --decrypt "$CACHE_FILE" >"$old_index_file"
  else
    : >"$old_index_file"
  fi

  # Copy old index as base for new index
  cp "$old_index_file" "$temp_new_index"

  # Function to update a single file in the index
  update_single_file() {
    local file="$1"
    local rel="${file#"$NOTES_DIR"/}"
    local size hash

    # Get current file stats
    if [[ "$(uname -s)" == "Darwin" ]]; then
      size=$(stat -f %z "$file")
      hash=$(md5 -q "$file")
    else
      size=$(stat -c %s "$file")
      hash=$(md5sum "$file" | awk '{print $1}')
    fi

    # Check if this file's hash has changed
    local old_hash
    old_hash=$(awk -F'|' -v rel="$rel" '$1==rel {print $3; exit}' "$old_index_file")

    if [[ "$hash" != "$old_hash" ]]; then
      # Remove old entries for this file
      awk -F'|' -v rel="$rel" '$1!=rel' "$temp_new_index" >"$tmpdir/temp_filtered"
      mv "$tmpdir/temp_filtered" "$temp_new_index"

      # Add new entries for this file
      gpg --quiet --decrypt "$file" | while IFS= read -r line; do
        printf "%s|%s|%s|%s\n" "$rel" "$size" "$hash" "$line"
      done >>"$temp_new_index"

      return 0 # File was updated
    fi

    return 1 # File was unchanged
  }

  local files_updated=0

  if [[ -n "$target_file" ]]; then
    # Update specific file only
    if [[ -f "$target_file" && "$target_file" == *.gpg ]]; then
      if update_single_file "$target_file"; then
        files_updated=1
        printf "Updated index for: %s\n" "${target_file#"$NOTES_DIR"/}"
      fi
    else
      printf "File not found or not a .gpg file: %s\n" "$target_file"
      return 1
    fi
  else
    # Smart incremental update: check all files but optimize for recent changes

    # First, remove entries for files that no longer exist
    local deleted_files="$tmpdir/deleted_files"
    local unique_files="$tmpdir/unique_files"

    # Get unique file paths from index
    awk -F'|' '{if(NF>=1 && $1!="") print $1}' "$old_index_file" | sort -u >"$unique_files"

    # Check which ones no longer exist on disk
    : >"$deleted_files"
    while read -r rel; do
      [[ -n "$rel" ]] || continue
      local full_path="$NOTES_DIR/$rel"
      if [[ ! -f "$full_path" ]]; then
        echo "$rel" >>"$deleted_files"
        printf "Found deleted file: %s\n" "$rel"
        files_updated=$((files_updated + 1))
      fi
    done <"$unique_files"

    # Remove all entries for deleted files
    if [[ -s "$deleted_files" ]]; then
      local temp_filtered="$tmpdir/temp_filtered"
      cp "$temp_new_index" "$temp_filtered"

      while read -r deleted_rel; do
        awk -F'|' -v rel="$deleted_rel" '$1!=rel' "$temp_filtered" >"$tmpdir/temp_work"
        mv "$tmpdir/temp_work" "$temp_filtered"
      done <"$deleted_files"

      mv "$temp_filtered" "$temp_new_index"
    fi

    # Then check all existing files
    local updated_count=0
    find "$NOTES_DIR" -type f -name "*.gpg" | while read -r file; do
      if update_single_file "$file"; then
        updated_count=$((updated_count + 1))
        printf "Updated: %s\n" "${file#"$NOTES_DIR"/}"
      fi
    done
    files_updated=$((files_updated + updated_count))
  fi

  # Only rewrite cache if something changed
  if [[ $files_updated -gt 0 ]] || [[ ! -f "$CACHE_FILE" ]]; then
    gpg --yes --batch --quiet --recipient "$KEY_ID" --encrypt --output "$CACHE_FILE" "$temp_new_index"

    local end_time
    end_time=$(date +%s)
    printf "Index updated (%d files changed) in %ds\n" $files_updated $((end_time - start_time))
  else
    printf "No changes detected\n"
  fi
}

# Convenience function for full rebuild (same as original behavior)
build_note_index() {
  update_note_index
}

# Fast single-file update (call this after creating/editing a note)
update_single_note() {
  local file="$1"
  if [[ -z "$file" ]]; then
    printf "Usage: update_single_note <file.gpg>\n"
    return 1
  fi
  update_note_index "$file"
}

# Quick check if index needs updating (doesn't actually update)
check_index_status() {
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf '"$tmpdir"'' EXIT

  local old_index_file="$tmpdir/old_index"
  local changes_found=0

  if [[ -f "$CACHE_FILE" ]]; then
    gpg --quiet --decrypt "$CACHE_FILE" >"$old_index_file"
  else
    printf "No index cache found\n"
    return 1
  fi

  printf "Checking index status...\n"

  # Check for deleted files
  while IFS='|' read -r rel size hash rest; do
    [[ -n "$rel" ]] || continue
    if [[ ! -f "$NOTES_DIR/$rel" ]]; then
      printf "DELETED: %s\n" "$rel"
      changes_found=1
    fi
  done <"$old_index_file"

  # Check for new/modified files
  find "$NOTES_DIR" -type f -name "*.gpg" | while read -r file; do
    local rel="${file#"$NOTES_DIR"/}"
    local size hash old_hash

    if [[ "$(uname -s)" == "Darwin" ]]; then
      size=$(stat -f %z "$file")
      hash=$(md5 -q "$file")
    else
      size=$(stat -c %s "$file")
      hash=$(md5sum "$file" | awk '{print $1}')
    fi

    old_hash=$(awk -F'|' -v rel="$rel" '$1==rel {print $3; exit}' "$old_index_file")

    if [[ -z "$old_hash" ]]; then
      printf "NEW: %s\n" "$rel"
      changes_found=1
    elif [[ "$hash" != "$old_hash" ]]; then
      printf "MODIFIED: %s\n" "$rel"
      changes_found=1
    fi
  done

  if [[ $changes_found -eq 0 ]]; then
    printf "Index is up to date\n"
  fi

  return $changes_found
}

# Updated function to search through the encrypted note index
grep() {
  local query="${1-""}"

  local temp_index=
  temp_index=$(mktemp)

  if [[ ! -f "$CACHE_FILE" ]]; then
    echo "Note index not found. Building it now..."
    update_note_index
  fi

  # Decrypt the single index file
  gpg --quiet --decrypt "$CACHE_FILE" >"$temp_index"

  local selected_line

  # Use awk to print only the filename and content, removing the hash.
  # The output is then piped directly to fzf.
  selected_line=$(awk -F'|' '{print $1 ":" $4}' "$temp_index" | fzf --ansi -q "$query")

  rm "$temp_index"

  if [[ -n "$selected_line" ]]; then
    # The filename is the first word on the selected line, up to the first colon
    local filename
    filename=$(echo "$selected_line" | awk -F: '{print $1}')

    # Call the edit_memo function with the extracted filename
    edit_memo "$NOTES_DIR/$filename"
  fi
}

# Main CLI entrypoint
# TODO: Add tests for this and make separate pars_args function
main() {
  # default "" when no arg is given
  local arg="${1-""}"

  CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"
  load_config "$CONFIG_FILE"
  gpg_key_exists "$KEY_ID"
  create_dirs

  # Handle default/editable memo inputs

  if [[ "$arg" == "edit" ]]; then
    shift
    edit_memo "$1"
    return
  fi

  if [[ "$arg" == "remove" ]]; then
    shift
    memo_remove "$1"
    return
  fi

  if [[ "$arg" == "find" ]]; then
    search_memo_filenames
    return
  fi

  if [[ "$arg" == "grep" ]]; then
    grep
    return
  fi

  if [[ "$arg" == "unlock" ]]; then
    shift
    unlock "$@"
    return
  fi

  if [[ "$arg" == "lock" ]]; then
    shift
    lock "$@"
    return
  fi

  if [[ "$arg" == "build-cache" ]]; then
    build_cache
    return
  fi

  if [[ "$arg" == "rebuild_cache" ]]; then
    sync_cache
    return
  fi

  if [[ "$arg" == "search_notes" ]]; then
    shift
    search_notes "$@"
    return
  fi

  if [[ "$arg" == "build_note_index" ]]; then
    update_note_index
    return
  fi

  if [[ "$arg" == "nsearch" ]]; then
    shift
    nsearch "$@"
    return
  fi

  if [[ "$arg" == "test" ]]; then
    memo_test
    return
  fi

  if [[ -z "$arg" || "$arg" == "today" || "$arg" == "yesterday" || "$arg" == "tomorrow" || "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || -n "$arg" ]]; then
    edit_memo "$arg"
    return
  fi

  # Default fallback
  echo "Usage: memo [edit|today|yesterday|YYYY-MM-DD|find|grep|lock|unlock]"
  exit 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly, NOT sourced
  main "$@"
fi
