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

get_hash() {
  local filename="$1"

  if [[ "$(uname -s)" == "Darwin" ]]; then
    md5 -q "$filename"
  else
    md5sum "$filename" | awk '{print $1}'
  fi
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

  # Resolve the absolute path of this script, following symlinks
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  local script_path
  script_path="$(cd -P "$(dirname "$SOURCE")" && pwd)"

  # Set defaults
  : "${KEY_IDS:=you@example.com}"
  : "${NOTES_DIR:=$HOME/notes}"
  : "${JOURNAL_NOTES_DIR:=$NOTES_DIR/journal}"
  : "${EDITOR_CMD:=${EDITOR:-nano}}"
  : "${CACHE_DIR:=$HOME/.cache/memo}"
  : "${CACHE_FILE:=$CACHE_DIR/notes.cache}"
  : "${CACHE_BUILDER_BIN:=$script_path/bin/cache_builder}"

  if file_exists "$config_file"; then
    # shellcheck source=/dev/null
    source "$config_file"
  else
    echo "Config file not found: $config_file" >&2
  fi

  if [ ! -x "$CACHE_BUILDER_BIN" ]; then
    echo "Building cache binary..."
    mkdir -p "$(dirname "$CACHE_BUILDER_BIN")"

    (cd "$script_path" && go build -o "$CACHE_BUILDER_BIN" ./cmd/cache_builder) || {
      echo "Error: Failed to build cache binary" >&2
      exit 1
    }

    chmod +x "$CACHE_BUILDER_BIN"
  fi
}

# TODO: Add tests for this
# Validate KEY_ID exists in GPG keyring
gpg_key_exists() {
  local key_ids="$1"
  local missing_keys=()

  IFS=',' read -ra keys <<<"$key_ids"
  for key in "${keys[@]}"; do
    key="$(echo "$key" | xargs)" # trim spaces
    if ! gpg --list-keys "$key" &>/dev/null; then
      missing_keys+=("$key")
    fi
  done

  if ((${#missing_keys[@]} > 0)); then
    echo "GPG key(s) not found: ${missing_keys[*]}" >&2
    exit 1
  fi
}

# TODO: Add tests for this
create_dirs() {
  # Create directories if not exist
  mkdir -p "$NOTES_DIR"
  mkdir -p "$JOURNAL_NOTES_DIR"
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

get_filepath() {
  local input="$1"
  local filename
  filename=$(determine_filename "$input")

  local filepath

  if filename_is_date "$filename"; then
    filepath="$JOURNAL_NOTES_DIR/$filename"
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

  recipients=()

  IFS=',' read -ra ids <<<"$KEY_IDS"
  for id in "${ids[@]}"; do
    id="$(echo "$id" | xargs)" # trim spaces

    if ! gpg_key_exists "$id"; then
      return 1
    fi

    recipients+=("-r" "$id")
  done

  gpg --quiet --yes --encrypt "${recipients[@]}" -o "$output_path" "$input_path"
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

# TODO: Add tests for this
# TODO: Can't we make this simpler by not asking for it. It can be annoying.
save_file() {
  local decrypted_file="$1"
  local encrypted_file="$2"

  # If the encrypted file doesn't exist, skip comparison and prompt for encryption
  if ! file_exists "$encrypted_file"; then
    encrypt_file "$decrypted_file" "$encrypted_file"
    build_notes_cache "$encrypted_file"
    return
  fi

  if should_encrypt_file "$decrypted_file" "$encrypted_file"; then
    encrypt_file "$decrypted_file" "$encrypted_file"
    build_notes_cache "$encrypted_file"
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

read_ignore_file() {
  local ignore_file=$NOTES_DIR/.ignore
  if file_exists "$ignore_file"; then
    # always ignore the .ignore file itself
    echo ".ignore"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac
      # print the pattern so the caller can capture it
      echo "$line"
    done <"$ignore_file"
  fi
}

# TODO: Add tests for this
lock() {
  local dry=0 target
  local exclude_patterns=()
  local ignore_patterns=()
  local recipients=()

  # capture .ignore → ignore_patterns[] (Bash 3.2 compatible)
  while IFS= read -r pat; do
    ignore_patterns[${#ignore_patterns[@]}]="$pat"
  done < <(read_ignore_file)

  # parse args
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

  # build recipients array from $KEY_IDS
  if [[ -z "$KEY_IDS" ]]; then
    echo "KEY_IDS not set"
    return 1
  fi

  IFS=',' read -ra ids <<<"$KEY_IDS"
  for id in "${ids[@]}"; do
    id="$(echo "$id" | xargs)" # trim spaces
    if ! gpg_key_exists "$id"; then
      echo "GPG key not found: $id"
      return 1
    fi
    recipients+=("-r" "$id")
  done

  if [[ "$target" == "all" ]]; then
    local files_to_encrypt=()

    while IFS= read -r file; do
      local rel="${file#"$NOTES_DIR"/}"

      # check .ignore patterns
      local skip=0
      for ig in "${ignore_patterns[@]}"; do
        # shellcheck disable=SC2053
        [[ "$rel" == $ig ]] && skip=1 && break
      done
      [[ $skip -eq 1 ]] && echo "Ignored (.ignore): $rel" && continue

      # check --exclude patterns
      for ex in "${exclude_patterns[@]}"; do
        # shellcheck disable=SC2053
        [[ "$rel" == $ex ]] && skip=1 && break
      done
      [[ $skip -eq 1 ]] && echo "Excluded (--exclude): $rel" && continue

      [[ $skip -eq 1 ]] && continue

      files_to_encrypt+=("$file")
    done < <(find "$NOTES_DIR" -type f ! -name "*.gpg")

    if [[ ${#files_to_encrypt[@]} -eq 0 ]]; then
      echo "Nothing to encrypt."
      return 0
    fi

    if [[ $dry -eq 1 ]]; then
      printf "Would encrypt: %s\n" "${files_to_encrypt[@]}"
    else
      gpg --encrypt-files --quiet --yes "${recipients[@]}" "${files_to_encrypt[@]}"

      local to_remove=()
      for f in "${files_to_encrypt[@]}"; do
        [[ -f "$f.gpg" ]] && to_remove+=("$f")
      done

      if ((${#to_remove[@]} > 0)); then
        rm -f "${to_remove[@]}"
        printf "Encrypted: %s\n" "${to_remove[@]}"
      fi
    fi
  else
    # resolve target file
    local file

    if [[ -f "$target" ]]; then
      file=$(realpath "$target")
    # else, search by basename under NOTES_DIR
    else
      file=$(find "$NOTES_DIR" -type f -name "$target" | head -n 1)
    fi

    if [[ -z "$file" ]]; then
      echo "Not found: $target"
      return 1
    fi

    if ! is_in_notes_dir "$file"; then
      echo "File not in $NOTES_DIR"
      return 1
    fi

    # compute path relative to NOTES_DIR
    local rel_file
    rel_file="${file#"$NOTES_DIR"/}"

    if [[ $dry -eq 1 ]]; then
      echo "Would encrypt: $rel_file"
    else
      gpg --encrypt-files --quiet --yes "${recipients[@]}" "$file"
      local enc_file="$file.gpg"
      if [[ -f "$enc_file" ]]; then
        rm -f "$NOTES_DIR/$file"
        echo "Encrypted: $rel_file"
      else
        echo "Encryption failed, keeping plaintext: $rel_file"
      fi
    fi
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

  read -rp "Are you sure you want to delete '$filepath'? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Deletion cancelled."
    return 1
  fi

  # Delete memo
  rm -f "$filepath"
  echo "Removed: $filepath"
  build_notes_cache "$filepath"
}

# --- Main ---
# Incrementally update note index
build_notes_cache() {
  local file="${1-""}"

  $CACHE_BUILDER_BIN "$NOTES_DIR" "$CACHE_FILE" "$KEY_IDS" "$file"
}

# Updated function to search through the encrypted note index
grep() {
  local query="${1-""}"

  local temp_index=
  temp_index=$(mktemp)

  if [[ ! -f "$CACHE_FILE" ]]; then
    echo "Note index not found. Building it now..."
    build_notes_cache
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
  gpg_key_exists "$KEY_IDS"
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

  if [[ "$arg" == "build_cache" ]]; then
    build_notes_cache
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
