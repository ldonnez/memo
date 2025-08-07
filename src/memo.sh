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

file_contents_are_equal() {
  local file1="$1"
  local file2="$2"

  if [[ ! -f "$file1" || ! -f "$file2" ]]; then
    return 1
  fi

  cmp -s "$file1" "$file2"
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
    echo "❌ GPG key not found for KEY_ID: $KEY_ID" >&2
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
    echo "$(date -d yesterday +%F).md"
    return 0
  fi

  if [[ "$input" == "tomorrow" ]]; then
    echo "$(date -d tomorrow +%F).md"
    return 0
  fi

  if [[ "$input" == *.md ]]; then
    echo "$input"
    return 0
  fi

  if [[ "$input" == *.gpg ]]; then
    echo "$input"
    return 0
  fi

  if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "$input.md"
    return 0
  fi

  >&2 echo "❌ Invalid input: $input"
  return 1
}

get_filepath() {
  local input="$1"
  local filename
  filename=$(determine_filename "$input")

  if filename_is_date "$filename"; then
    echo "$DAILY_NOTES_DIR/$filename"
  else
    echo "$NOTES_DIR/$filename"
  fi
}

gpg_encrypt() {
  # Sets output_path to input_path when output_path is not given
  local input_path="$1" output_path="${2-$1}"

  gpg --quiet --yes --encrypt -r "$KEY_ID" -o "$output_path.gpg" "$input_path"
  echo "✅ Encrypted: $output_path.gpg"
}

gpg_decrypt() {
  local input_path="$1" output_path="$2"

  gpg --quiet --decrypt "$input_path" >"$output_path" || {
    echo "❌ Failed to decrypt $input_path"
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
reencrypt_if_confirmed() {
  local decrypted_file="$1"
  local encrypted_file="$2"

  # If the encrypted file doesn't exist, skip comparison and prompt for encryption
  if ! file_exists "$encrypted_file.gpg"; then
    echo -n "💾 Save and encrypt this new memo? (y/N): "
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      encrypt_file "$decrypted_file" "$encrypted_file"
    else
      echo "❌ New memo discarded."
    fi
    return
  fi

  if should_encrypt_file "$decrypted_file" "$encrypted_file"; then
    echo -n "💾 Re-encrypt changes to original file? (y/N): "
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      encrypt_file "$decrypted_file" "$encrypted_file"
    else
      echo "❌ Changes discarded."
    fi
  else
    echo "✅ No changes detected. Skipping re-encryption."
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

  if is_file_older_than "$plaintext" "$encrypted_file"; then
    return 1
  fi

  local tmp_file
  tmp_file=$(make_tempfile "$encrypted_file")

  if file_contents_are_equal "$plaintext" "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  else
    rm -f "$tmp_file"
    return 0
  fi
}

encrypt_file() {
  local input_file="$1" output_file="$2" dry="$3"

  if [[ "$dry" -eq 1 ]]; then
    echo "📝 Would encrypt: $input_file → $output_file.gpg"
    echo "🧹 Would delete: $input_file"
  else
    gpg_encrypt "$input_file" "$output_file" && {
      update_cache_file "$output_file.gpg"
      rm -f "$input_file"
    }
  fi
}

# Commands
# TODO: Add tests for this
edit_memo() {
  local input="$1"
  local filepath
  filepath=$(get_filepath "$input") || return 1
  local tmpfile
  tmpfile=$(make_tempfile "${filepath##*/}")

  if [[ -f "$filepath.gpg" ]]; then
    gpg_decrypt "$filepath.gpg" "$tmpfile"
  else
    header=$(strip_extensions "$(strip_path "$filepath")")
    echo "# $header" >"$tmpfile"
    echo "" >>"$tmpfile"
  fi

  "$EDITOR_CMD" "$tmpfile"
  reencrypt_if_confirmed "$tmpfile" "$filepath"
  shred -u "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
}

# TODO: Add tests for this
unlock() {
  local target="$1"
  if [[ -z "$target" ]]; then
    echo "❌ Usage: memo unlock <filename.gpg | all>"
    return 1
  fi

  if [[ "$target" == "all" ]]; then
    find "$NOTES_DIR" -type f -name "*.gpg" | while read -r file; do
      local plaintext="${file%.gpg}"
      [[ -f "$plaintext" ]] && echo "⚠️ Skipping: $plaintext" && continue
      gpg_decrypt "$file" "$plaintext" && echo "✅ Decrypted: $plaintext"
    done
  else
    local file
    file=$(find "$NOTES_DIR" -type f -name "$target" | head -n 1)
    [[ -z "$file" ]] && echo "❌ File not found: $target" && return 1
    local plaintext="${file%.gpg}"
    [[ -f "$plaintext" ]] && echo "⚠️ Already exists: $plaintext" && return 1
    gpg_decrypt "$file" "$plaintext" && echo "✅ Decrypted: $plaintext"
  fi
  echo "🧼 Run 'memo lock all' to re-encrypt"
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
    echo "❌ Usage: memo lock <filename | all> [--dry-run] [--exclude pattern]"
    return 1
  fi

  if [[ "$target" == "all" ]]; then
    find "$NOTES_DIR" -type f ! -name "*.gpg" | while read -r file; do
      is_ignored_path "$file" && continue

      for pattern in "${exclude_patterns[@]}"; do
        [[ $(basename "$file") == "$pattern" ]] && echo "⏭️ Skipping: $file" && continue 2
      done
      local encfile="$file.gpg"
      should_encrypt_file "$file" "$encfile" && encrypt_file "$file" "$file" "$dry"
    done
  else
    local file
    file=$(find "$NOTES_DIR" -type f -name "$target" | head -n 1)
    [[ -z "$file" ]] && echo "❌ Not found: $target" && return 1
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
  reencrypt_if_confirmed "$tmpfile" "$result"
}

# TODO: Add tests for this
live_grep_memos() {
  local dec_files=()
  while IFS= read -r -d $'\0' file; do
    dec_files+=("$file")
  done < <(find "$CACHE_DIR" -type f -print0)

  [[ ${#dec_files[@]} -eq 0 ]] && echo "⚠️ No notes to search." && return 0

  local result
  result=$(rg --with-filename --line-number "" "${dec_files[@]}" |
    fzf --ansi --delimiter : \
      --preview 'bat --style=numbers --color=always {1} --line-range {2}: ' \
      --preview-window=up:40%)

  [[ -z "$result" ]] && return 0

  local dec_file line
  dec_file=$(echo "$result" | cut -d: -f1)
  line=$(echo "$result" | cut -d: -f2)

  # Map cached decrypted file back to encrypted file
  local enc_file="$NOTES_DIR/${dec_file#"$CACHE_DIR"/}.gpg"

  "$EDITOR_CMD" "+$line" "$dec_file"
  reencrypt_if_confirmed "$dec_file" "$enc_file"
}

memo_test() {
  echo "NOTHING TO TEST"
}

# TODO: Add tests for this
memo_remove() {
  local input="$1"
  [[ -z "$input" ]] && echo "❌ No memo filename provided." && return 1

  # Normalize filename: append .gpg if missing
  [[ "$input" != *.gpg ]] && input="${input}.gpg"

  local filepath="$NOTES_DIR/$input"
  if [[ ! -f "$filepath" ]]; then
    echo "❌ Memo not found: $filepath"
    return 1
  fi

  read -rp "🗑️  Are you sure you want to delete '$filepath'? [y/N] " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Deletion cancelled."
    return 1
  fi

  # Delete memo
  rm -f "$filepath"
  echo "✅ Removed: $filepath"

  # Remove from cache if present
  if [[ -n "$CACHE_DIR" ]]; then
    local relpath decfile
    relpath=$(realpath --relative-to="$NOTES_DIR" "$filepath")
    decfile="$CACHE_DIR/${relpath%.gpg}"
    if [[ -f "$decfile" ]]; then
      rm -f "$decfile"
      echo "🧹 Cache cleaned: $decfile"
    fi
  fi
}

# TODO: Add tests for this
build_cache() {
  echo "🔄 Building cache from encrypted notes..."

  while IFS= read -r -d '' encfile; do
    update_cache_file "$encfile"
  done < <(find "$NOTES_DIR" -type f -name '*.gpg' -print0)

  while IFS= read -r -d '' cached_file; do
    rel_cached="${cached_file#"$CACHE_DIR"/}"
    enc_path="$NOTES_DIR/${rel_cached}.gpg"
    if [[ ! -f "$enc_path" ]]; then
      echo "🧹 Removing stale cache: $rel_cached"
      rm -f "$cached_file"
    fi
  done < <(find "$CACHE_DIR" -type f -print0)

  echo "✅ Cache build complete."
}

# Main CLI entrypoint
# TODO: Add tests for this
main() {
  local arg="$1"

  CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"
  load_config "$CONFIG_FILE"
  gpg_key_exists "$KEY_ID"
  create_dirs

  # Handle default/editable memo inputs
  if [[ -z "$arg" || "$arg" == "today" || "$arg" == "yesterday" || "$arg" == "tomorrow" || "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || "$arg" == *.md || "$arg" == *.gpg ]]; then
    edit_memo "$arg"
    return
  fi

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
    live_grep_memos
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

  if [[ "$arg" == "test" ]]; then
    memo_test
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
