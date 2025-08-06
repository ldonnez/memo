#!/usr/bin/env bash

# Load config
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"
# shellcheck source=/dev/null
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Set defaults
: "${KEY_ID:=you@example.com}"
: "${NOTES_DIR:=$HOME/notes}"
: "${DAILY_NOTES_DIR:=$NOTES_DIR/dailies}"
: "${EDITOR_CMD:=${EDITOR:-nano}}"
: "${CACHE_DIR:=$HOME/.cache/memo}"

# Create directories if not exist
mkdir -p "$NOTES_DIR"
mkdir -p "$DAILY_NOTES_DIR"
mkdir -p "$CACHE_DIR"
chmod 700 "$CACHE_DIR" # Ensure only current user can write to .cache dir.

IGNORE_PATTERNS=(
  "*.bak"
  "*.tmp"
  ".git"
  ".DS_Store"
  "README.md"
)

# Helpers
is_ignored_path() {
  local path="$1"
  for ignore in "${IGNORE_PATTERNS[@]}"; do
    [[ "$path" == *"/$ignore/"* || "$path" == *"/$ignore/"*/* ]] && return 0
  done
  return 1
}

get_filepath() {
  local input="$1"
  case "$input" in
  "" | "today") date=$(date +%F) ;;
  "yesterday") date=$(date -v-1d +%F 2>/dev/null || date -d yesterday +%F) ;;
  "tomorrow") date=$(date -v+1d +%F 2>/dev/null || date -d tomorrow +%F) ;;
  *.md)
    echo "$NOTES_DIR/$input.gpg"
    return
    ;;
  *.gpg)
    echo "$NOTES_DIR/$input"
    return
    ;;
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) date="$input" ;;
  *)
    echo "❌ Invalid input: $input"
    return 1
    ;;
  esac
  echo "$DAILY_NOTES_DIR/$date.md.gpg"
}

get_secure_tempfile() {
  local encfile="$1"
  local relname="${encfile##*/}" # e.g., 2025-08-06.md.gpg
  local base="${relname%.gpg}"   # remove .gpg → 2025-08-06.md

  local tmpdir
  if [[ -d /dev/shm ]]; then
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
  tmpfile=$(get_secure_tempfile "$basename")
  if gpg --quiet --decrypt "$encfile" >"$tmpfile"; then
    echo "$tmpfile"
  else
    echo ""
    return 1
  fi
}

update_cache_file() {
  local encfile="$1"
  local relpath
  relpath=$(realpath --relative-to="$NOTES_DIR" "$encfile")
  local decfile="$CACHE_DIR/${relpath%.gpg}"
  mkdir -p "$(dirname "$decfile")"
  gpg --quiet --decrypt "$encfile" >"$decfile" || rm -f "$decfile"
}

reencrypt_if_confirmed() {
  local decrypted_file="$1"
  local encrypted_file="$2"

  # If the encrypted file doesn't exist, skip comparison and prompt for encryption
  if [[ ! -f "$encrypted_file" ]]; then
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

# === Core Commands ===
edit_memo() {
  local input="$1"
  local filepath
  filepath=$(get_filepath "$input") || return 1
  local tmpfile
  tmpfile=$(get_secure_tempfile "${filepath##*/}")

  if [[ -f "$filepath" ]]; then
    gpg --quiet --decrypt "$filepath" >"$tmpfile" || {
      echo "❌ Failed to decrypt $filepath"
      return 1
    }
  else
    header=$(strip_extensions "$(strip_path "$filepath")")
    echo "# $header" >"$tmpfile"
    echo "" >>"$tmpfile"
  fi

  "$EDITOR_CMD" "$tmpfile"
  reencrypt_if_confirmed "$tmpfile" "$filepath"
  shred -u "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
}

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
      gpg --quiet --decrypt "$file" >"$plaintext" && echo "✅ Decrypted: $plaintext"
    done
  else
    local file
    file=$(find "$NOTES_DIR" -type f -name "$target" | head -n 1)
    [[ -z "$file" ]] && echo "❌ File not found: $target" && return 1
    local plaintext="${file%.gpg}"
    [[ -f "$plaintext" ]] && echo "⚠️ Already exists: $plaintext" && return 1
    gpg --quiet --decrypt "$file" >"$plaintext" && echo "✅ Decrypted: $plaintext"
  fi
  echo "🧼 Run 'memo lock all' to re-encrypt"
}

should_encrypt_file() {
  local plaintext="$1" encfile="$2"
  [[ ! -f "$encfile" ]] && return 0
  [[ "$plaintext" -ot "$encfile" ]] && return 1

  local tmp_dec
  tmp_dec=$(mktemp)
  gpg --quiet --decrypt "$encfile" >"$tmp_dec" || return 0
  cmp -s "$plaintext" "$tmp_dec"
  local result=$?
  rm -f "$tmp_dec"
  return $((!result))
}

encrypt_file() {
  local plaintext="$1" encfile="$2" dry="$3"
  if [[ "$dry" -eq 1 ]]; then
    echo "📝 Would encrypt: $plaintext → $encfile"
    echo "🧹 Would delete: $plaintext"
  else
    gpg --quiet --yes --encrypt -r "$KEY_ID" -o "$encfile" "$plaintext" && {
      echo "✅ Encrypted: $encfile"
      update_cache_file "$encfile"
      rm -f "$plaintext"
    }
  fi
}

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
      should_encrypt_file "$file" "$encfile" && encrypt_file "$file" "$encfile" "$dry"
    done
  else
    local file
    file=$(find "$NOTES_DIR" -type f -name "$target" | head -n 1)
    [[ -z "$file" ]] && echo "❌ Not found: $target" && return 1
    local encfile="$file.gpg"
    should_encrypt_file "$file" "$encfile" && encrypt_file "$file" "$encfile" "$dry"
  fi
}

search_memo_filenames() {
  local result
  result=$(find "$NOTES_DIR" -type f -name "*.gpg" | fzf --preview "gpg --quiet --decrypt {} 2>/dev/null | head -100")
  [[ -z "$result" ]] && return
  local tmpfile
  tmpfile=$(decrypt_file_to_temp "$result") || return
  "$EDITOR_CMD" "$tmpfile"
  reencrypt_if_confirmed "$tmpfile" "$result"
}

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

# === Main CLI ===
case "$1" in
"" | today | yesterday | tomorrow | [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] | *.md | *.gpg)
  edit_memo "$1"
  ;;
edit)
  shift
  edit_memo "$1"
  ;;
remove)
  shift
  memo_remove "$1"
  ;;
find)
  search_memo_filenames
  ;;
grep)
  live_grep_memos
  ;;
unlock)
  shift
  unlock "$@"
  ;;
lock)
  shift
  lock "$@"
  ;;
build-cache)
  build_cache
  ;;
*)
  echo "Usage: memo [edit|today|yesterday|YYYY-MM-DD|find|grep|lock|unlock]"
  exit 1
  ;;
esac
