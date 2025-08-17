#!/usr/bin/env bash

set -euo pipefail

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

filename_is_date() {
  local filename="$1"

  # Strip path and isolate base name
  filename="${filename##*/}"

  # Example: 2025-08-05.md.gpg → 2025-08-05
  local base="${filename%%.*}"

  # Check if base name matches YYYY-MM-DD format
  if [[ "$base" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    return 0
  else
    return 1
  fi
}

# Resolve the absolute path of where this script is run (it follows symlinks)
get_script_path() {
  local source="${BASH_SOURCE[0]}"
  while [ -h "$source" ]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" && pwd)"

    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

# Build the cache_builder binary if not found
build_cache_binary() {
  local script_path="$1"
  local binary="$2"

  if [ ! -x "$binary" ]; then
    printf "Building cache binary...\n"
    mkdir -p "$(dirname "$binary")"

    (cd "$script_path" && go build -o "$binary" ./cmd/cache_builder) || {
      printf "Error: Failed to build cache binary\n" >&2
      exit 1
    }

    chmod +x "$binary"
  fi
}

# Set default values if unset
set_default_values() {
  : "${KEY_IDS:=}"
  : "${NOTES_DIR:=$HOME/notes}"
  : "${JOURNAL_NOTES_DIR:=$NOTES_DIR/journal}"
  : "${EDITOR_CMD:=${EDITOR:-nano}}"
  : "${CACHE_DIR:=$HOME/.cache/memo}"
  : "${CACHE_FILE:=$CACHE_DIR/notes.cache}"
  : "${CACHE_BUILDER_BIN:=$1/bin/cache_builder}"
}

# TODO: Add tests for this
load_config() {
  local config_file="$1"
  local script_path="$2"

  set_default_values "$script_path"

  if file_exists "$config_file"; then
    # shellcheck source=/dev/null
    source "$config_file"
  else
    printf "Config file not found: %s\n" "$config_file" >&2
  fi

}

trim() {
  local string="$1"

  # trim leading spaces
  string="${string#"${string%%[! ]*}"}"

  # trim trailing spaces
  string="${string%"${string##*[! ]}"}"
  printf "%s" "$string"
}

# Validates if all the given key_ids exist in GPG keyring
gpg_keys_exists() {
  local key_ids="$1"
  local missing_keys=()

  IFS=',' read -ra keys <<<"$key_ids"
  for key in "${keys[@]}"; do
    key="$(trim "$key")"

    if ! gpg --list-keys "$key" &>/dev/null; then
      missing_keys+=("$key")
    fi
  done

  if ((${#missing_keys[@]} > 0)); then
    printf "GPG key(s) not found: %s\n" "${missing_keys[*]}" >&2
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
    printf "%s.md" "$(date +%F)"
    return 0
  fi

  if [[ "$input" == "yesterday" ]]; then
    printf "%s.md" "$(date -d "yesterday" +%F 2>/dev/null || date -v-1d +%F)"
    return 0
  fi

  if [[ "$input" == "tomorrow" ]]; then
    printf "%s.md" "$(date -d "tomorrow" +%F 2>/dev/null || date -v+1d +%F)"
    return 0
  fi

  if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf "%s.md" "$input"
    return 0
  fi

  printf "%s" "$input"
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

  printf "%s" "$filepath"
}

gpg_encrypt() {
  # Sets output_path to input_path when output_path is not given
  local input_path="$1" output_path="${2-$1}"

  recipients=()

  IFS=',' read -ra ids <<<"$KEY_IDS"
  for id in "${ids[@]}"; do
    id="$(trim "$id")"

    if ! gpg_keys_exists "$id"; then
      return 1
    fi

    recipients+=("-r" "$id")
  done

  gpg --quiet --yes --encrypt "${recipients[@]}" -o "$output_path" "$input_path"
  printf "Encrypted: %s\n" "$output_path"
}

gpg_decrypt() {
  local input_path="$1" output_path="$2"

  gpg --quiet --yes --decrypt "$input_path" >"$output_path" || {
    printf "Failed to decrypt %s\n" "$input_path"
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
    tmpdir=$(mktemp -d 2>/dev/null || printf "/tmp")
  fi

  local tmpfile="$tmpdir/memo-${base}"
  printf "%s" "$tmpfile"
}

decrypt_file_to_temp() {
  local encfile="$1"
  local basename="${encfile##*/}"
  local tmpfile
  tmpfile=$(make_tempfile "$basename")

  if gpg_decrypt "$encfile" "$tmpfile"; then
    printf "%s" "$tmpfile"
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
  printf "%s" "${filepath##*/}"
}

strip_extensions() {
  local filename="$1"
  while [[ "$filename" == *.* ]]; do
    filename="${filename%.*}"
  done
  printf "%s" "$filename"
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
    printf "Would encrypt: %s → %s.gpg\n" "$input_file" "$output_file"
    printf "Would delete: %s\n" "$input_file"
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
      printf "%s" "$fullpath"
      return
    else
      printf "Error: File is not a valid gpg memo in the notes directory.\n" >&2
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
    printf "# %s\n\n" "$header" >"$tmpfile"
  fi

  printf "%s\n" "$tmpfile"
}

find_note_file() {
  local target="$1"
  local file=""

  if [[ -f "$target" ]]; then
    file=$(realpath "$target")
  else
    file=$(find "$NOTES_DIR" -type f -path "*/$target" | head -n 1)
  fi

  if ! file_exists "$file"; then
    printf "Not found: %s\n" "$target"
    return 1
  fi

  if ! is_in_notes_dir "$file"; then
    printf "File not in %s\n" "$NOTES_DIR"
    return 1
  fi

  printf "%s" "$file"
}

# Commands
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

memo_decrypt() {
  local target="$1"
  if [[ -z "$target" ]]; then
    printf "Usage: memo --decrypt <filename.gpg | all>\n"
    return 1
  fi

  if [[ "$target" == "all" ]]; then
    gpg --yes --decrypt-files "$NOTES_DIR"/*.gpg "$NOTES_DIR"/**/*.gpg
  else
    local target="$1"

    if file=$(find_note_file "$target"); then

      local plaintext="${file%.gpg}"

      gpg_decrypt "$file" "$plaintext" && printf "Decrypted: %s\n" "$plaintext"
    else
      printf "File not in %s\n" "$NOTES_DIR"
      return 1
    fi
  fi
}

read_ignore_file() {
  local ignore_file=$NOTES_DIR/.ignore
  if file_exists "$ignore_file"; then
    # always ignore the .ignore file itself
    printf ".ignore\n"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac
      # print the pattern so the caller can capture it
      printf "%s\n" "$line"
    done <"$ignore_file"
  fi
}

memo_encrypt() {
  local dry=0 target
  local exclude_patterns=()
  local ignore_patterns=()

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
    printf "Usage: memo encrypt <filename | all> [--dry-run] [--exclude pattern]\n"
    return 1
  fi

  local recipients=()
  IFS=',' read -ra ids <<<"$KEY_IDS"

  for id in "${ids[@]}"; do
    id="$(trim "$id")" # trim spaces
    if ! gpg_keys_exists "$id"; then
      printf "GPG key not found: %s\n" "$id"
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
      if [[ "${#ignore_patterns[@]}" -gt 0 ]]; then
        for ig in "${ignore_patterns[@]}"; do
          # shellcheck disable=SC2053
          [[ "$rel" == $ig ]] && skip=1 && break
        done
        [[ $skip -eq 1 ]] && printf "Ignored (.ignore): %s\n" "$rel" && continue
      fi

      # check --exclude patterns
      if [[ "${#exclude_patterns[@]}" -gt 0 ]]; then
        for ex in "${exclude_patterns[@]}"; do
          # shellcheck disable=SC2053
          [[ "$rel" == $ex ]] && skip=1 && break
        done
        [[ $skip -eq 1 ]] && printf "Excluded (--exclude): %s\n" "$rel" && continue
      fi

      [[ $skip -eq 1 ]] && continue

      files_to_encrypt+=("$file")
    done < <(find "$NOTES_DIR" -type f ! -name "*.gpg")

    if [[ ${#files_to_encrypt[@]} -eq 0 ]]; then
      printf "Nothing to encrypt.\n"
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
    if file=$(find_note_file "$target"); then
      local rel_file
      rel_file="${file#"$NOTES_DIR"/}"
      if [[ $dry -eq 1 ]]; then
        printf "Would encrypt: %s\n" "$rel_file"
      else
        gpg --encrypt-files --quiet --yes "${recipients[@]}" "$file"
        local enc_file="$file.gpg"
        if [[ -f "$enc_file" ]]; then
          rm -f "$NOTES_DIR/$file"
          printf "Encrypted: %s\n" "$rel_file"
        else
          printf "Encryption failed, keeping plaintext: %s\n" "$rel_file"
        fi
      fi
    else
      printf "File not in %s\n" "$NOTES_DIR"
      return 1
    fi
  fi
}

find_memos() {
  local result

  result=$(rg --files --glob "*.gpg" "$NOTES_DIR" | fzf --preview "gpg --quiet --decrypt {} 2>/dev/null | head -100")

  [[ -z "$result" ]] && return

  edit_memo "$result"
}

# TODO: Add tests for this
memo_remove() {
  local target="$1"
  [[ -z "$target" ]] && printf "No memo filename provided.\n" && return 1

  if file=$(find_note_file "$target"); then
    read -rp "Are you sure you want to delete '$file'? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      printf "Deletion cancelled.\n"
      return 1
    fi

    # Delete memo
    rm -f "$file"
    printf "Removed: %s\n" "$file"
    build_notes_cache "$file"
  else
    printf "Memo not found: %s\n" "$target"
  fi
}

# --- Main ---
# Incrementally update note index
build_notes_cache() {
  local file="${1-""}"

  $CACHE_BUILDER_BIN "$NOTES_DIR" "$CACHE_FILE" "$KEY_IDS" "$file"
}

grep() {
  local query="${1-""}"

  local temp_index=
  temp_index=$(mktemp)

  if [[ ! -f "$CACHE_FILE" ]]; then
    printf "Cache not found. Building it now...\n"
    build_notes_cache
  fi

  gpg_decrypt "$CACHE_FILE" "$temp_index"

  local selected_line

  # Print only the filename and content, removing the size and hash.
  selected_line=$(awk -F'|' '{print $1 ":" $4}' "$temp_index" | fzf --ansi -q "$query")

  rm "$temp_index"

  if [[ -n "$selected_line" ]]; then
    # The filename is the first word on the selected line, up to the first colon eg. "filename.md.gpg:content"
    local filename
    filename=$(printf "%s" "$selected_line" | awk -F: '{print $1}')

    edit_memo "$NOTES_DIR/$filename"
  fi
}

show_help() {
  cat <<EOF
Usage: memo [OPTIONS] [COMMAND] [ARGS]

Options:
  -h, --help                Show this help message and exit

Commands:
  --remove MEMO             Remove a memo
  --find                    List all memos in $NOTES_DIR with rg and fzf
  --grep                    Uses rg and the $CACHE_FILE to grep all notes
  --decrypt [filename|all]  Decrypt one or all memos
  --encrypt [filename|all]  Encrypt one or all memos
  --cache                   Builds the cache file (incrementally)
  today                     Shortcut for editing today's memo
  yesterday                 Shortcut for editing yesterday's memo
  tomorrow                  Shortcut for editing tomorrow's memo
  YYYY-MM-DD                Edit memo for a specific date
EOF
}

parse_args() {
  local arg="${1-""}"

  while [ $# -gt 0 ]; do
    case "$1" in
    --help)
      show_help
      exit 0
      ;;
    --remove)
      shift
      memo_remove "$1"
      return
      ;;
    --find)
      find_memos
      return
      ;;
    --grep)
      grep
      return
      ;;
    --decrypt)
      shift
      memo_encrypt "$@"
      return
      ;;
    --encrypt)
      shift
      memo_encrypt "$@"
      return
      ;;
    --cache)
      build_notes_cache
      return
      ;;
    --) # end of options
      shift
      break
      ;;
    -*) # unknown short option
      show_help
      exit 1
      ;;
    *) # positional argument (subcommand/date)
      arg="$1"
      shift
      break
      ;;
    esac
  done

  if [[ -z "$arg" || "$arg" == "today" || "$arg" == "yesterday" || "$arg" == "tomorrow" || "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || -n "$arg" ]]; then
    edit_memo "$arg"
    return
  fi

  # unknown command
  printf "Usage: memo [today|esterday|YYYY-MM-DD|--find|--grep|--encrypt|--decrypt|--cache]\n"
  exit 1
}

# Entrypoint
main() {
  local script_path
  script_path="$(get_script_path)"

  CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"
  load_config "$CONFIG_FILE" "$script_path"
  gpg_keys_exists "$KEY_IDS"
  create_dirs
  build_cache_binary "$script_path" "$CACHE_BUILDER_BIN"

  parse_args "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly, NOT sourced
  main "$@"
fi
