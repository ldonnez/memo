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

# Check if command exists in PATH
check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Check if filename matches YYYY-MM-DD format.
# Strips path and extensions before determining. (e.g example.md.gpg -> example)
filename_is_date() {
  local filepath="$1"

  # Example: 2025-08-05.md.gpg → 2025-08-05
  local filename
  filename=$(strip_extensions "$(strip_path "$filepath")")

  if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    return 0
  else
    return 1
  fi
}

# Resolves the absolute path of where this script is run (it will follows symlinks)
resolve_script_path() {
  local source="${BASH_SOURCE[0]}"
  while [ -h "$source" ]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" && pwd)"

    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

# Build the cache_builder binary if not found and puts it in the bin directory relative to script path (the location where the script is ran from)
build_cache_builder_binary() {
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

# Set default global variables
set_default_values() {
  local script_path="$1"

  : "${KEY_IDS:=}"
  : "${NOTES_DIR:=$HOME/notes}"
  : "${JOURNAL_NOTES_DIR:=$NOTES_DIR/journal}"
  : "${EDITOR_CMD:=${EDITOR:-nano}}"
  : "${CACHE_DIR:=$HOME/.cache/memo}"
  : "${CACHE_FILE:=$CACHE_DIR/notes.cache}"
  : "${CACHE_BUILDER_BIN:=$script_path/bin/cache_builder}"
  : "${MEMO_NEOVIM_INTEGRATION:=true}"
}

# Loads config from config file (default: ~/.config/memo/config)
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

# Trim leading or trailing spaces of a string
trim() {
  local string="$1"

  # trim leading spaces
  string="${string#"${string%%[! ]*}"}"

  # trim trailing spaces
  string="${string%"${string##*[! ]}"}"
  printf "%s" "$string"
}

# Validates if all the given key_ids exist in GPG keyring.
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

# Initializes $NOTES_DIR, $JOURNAL_NOTES_DIR, $CACHE_DIR
create_dirs() {
  # Create directories if not exist
  mkdir -p "$NOTES_DIR"
  mkdir -p "$JOURNAL_NOTES_DIR"
  mkdir -p "$CACHE_DIR"
  chmod 700 "$CACHE_DIR" # Ensure only current user can write to .cache dir.
}

# Maps today, yesterday, tomorrow to YYYY-MM-DD date.
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

# Returns filepath based on input file name.
# When input filename is date, the file is classified as a file belonging in the journals directory ($JOURNAL_NOTES_DIR.
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

# Builds the gpg recipients (-r param in gpg) based on given key_ids
# When no key_ids is empty --default-recipient-self is given, which means the first key found in the keyring is used as a recipient.
# returns array of "-r <key_id> -r <key_id2>"
#
# Usage:
#
# ```
# local -a recipients=()
#
# if ! build_gpg_recipients "$KEY_IDS" recipients; then
#   return 1
# fi
#
# gpg --quiet --yes --armor --encrypt "${recipients[@]}"...
# ```
build_gpg_recipients() {
  local key_ids="$1"
  local output_array="$2"

  if [[ -z "$key_ids" ]]; then
    eval "$output_array+=(\"--default-recipient-self\")"
    return 0
  fi

  local IFS=',' items
  read -r -a items <<<"$key_ids"

  if [[ ${#items[@]} -eq 0 ]]; then
    eval "$output_array+=(\"--default-recipient-self\")"
    return 0
  fi

  local id
  for id in "${items[@]}"; do
    id=$(trim "$id")
    [[ -z "$id" ]] && continue

    if ! gpg_keys_exists "$id"; then
      printf "GPG key(s) not found: %s\n" "$id" >&2
      return 1
    fi

    eval "$output_array+=(\"-r\" \"$id\")"
  done
}

# Encrypts the content of given input file (path) to given output file (path)
# This will NOT encrypt the file itself only the content. (gpg --armor)
gpg_encrypt() {
  # Sets output_path to input_path when output_path is not given
  local input_path="$1" output_path="${2-$1}"

  if ! file_exists "$input_path"; then
    printf "File not found: %s" "$input_path"
    exit 1
  fi

  local -a recipients=()

  if ! build_gpg_recipients "$KEY_IDS" recipients; then
    return 1
  fi

  gpg --quiet --yes --armor --encrypt "${recipients[@]}" -o "$output_path" "$input_path"
}

# Decrypts given input file (path) to given output file (path)
# When output_path is not given (default) it will decrypt content to stdout. This is important when decrypting to external buffers like in Neovim.
gpg_decrypt() {
  local input_path="$1" output_path="${2-""}"

  if ! file_exists "$input_path"; then
    printf "File not found: %s" "$input_path"
    exit 1
  fi

  # Send output to stdout.
  if [[ -z "$output_path" ]]; then
    gpg --quiet --yes --decrypt "$input_path" || {
      printf "Failed to decrypt %s\n" "$input_path" >&2
      return 1
    }
  else
    # Redirect output to the specified file.
    gpg --quiet --yes --decrypt "$input_path" >"$output_path" || {
      printf "Failed to decrypt %s\n" "$input_path" >&2
      return 1
    }
  fi
}

# Creates a tempfile used for temporary storing decrypted content.
# When on Linux it will create the tempfile on memory (/dev/shm), otherwise (e.g MacOS) /tmp is used.
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

# /path/to/example.md -> example.md
strip_path() {
  local filepath="$1"
  printf "%s" "${filepath##*/}"
}

# example.md.gpg -> example
strip_extensions() {
  local filename="$1"
  while [[ "$filename" == *.* ]]; do
    filename="${filename%.*}"
  done
  printf "%s" "$filename"
}

# Checks if given path is inside $NOTES_DIR. Also works if the file is in subdir of $NOTES_DIR
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

# Determines destination path of given input.
# Given empty will get classified as daily memo e.g YYYY-MM-DD
# When file or path is inside notes directory ($NOTES_DIR) it will return the fullpath path of the input file. This also works when working dir is inside the notes dir. For example `cd $NOTES_DIR/example/example.md.gpg` -> `get_target_filepath "example.md.gpg"` returns the full path of example.md.gpg.
# New file will get created if input does not exist.
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

# Finds note file path relative of $NOTES_DIR.
# When working dir is inside $NOTES_DIR it will return the path relat
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

# Edits given file in temporary file.
# Creates new file with filename as header if not exists. e.g example.md -> # example
make_or_edit_file() {
  local filepath="$1"

  local tmpfile
  tmpfile=$(make_tempfile "${filepath##*/}")

  local gpg_file
  if gpg_file=$(get_gpg_filepath "$filepath"); then
    gpg_decrypt "$gpg_file" "$tmpfile"
  else
    create_file_header "$filepath" "$tmpfile"
  fi

  printf "%s\n" "$tmpfile"
}

# Determines correct GPG file path
get_gpg_filepath() {
  local filepath="$1"

  if file_exists "$filepath.gpg"; then
    printf "%s.gpg\n" "$filepath"
  elif file_is_gpg "$filepath"; then
    printf "%s\n" "$filepath"
  else
    return 1
  fi
}

# Determines the output GPG file path used before encryption
get_output_gpg_filepath() {
  local filepath="$1"

  if file_is_gpg "$filepath"; then
    printf "%s\n" "$filepath"
  else
    printf "%s.gpg\n" "$filepath"
  fi
}

# Creates a file header used when new file is created
create_file_header() {
  local filepath="$1"
  local output_file="$2"

  local header
  header=$(strip_extensions "$(strip_path "$filepath")")
  printf "# %s\n\n" "$header" >"$output_file"
}

# Loads ignore file into space separated string.
#
# Usage:
#
# ```
# local -a ignore_patterns=()
#
# while IFS= read -r pat; do
#   ignore_patterns+=("$pat")
# done < <(read_ignore_file)
# ```
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

memo_files() {
  if ! check_cmd gpg || ! check_cmd rg || ! check_cmd fzf; then
    printf "Error: gpg, rg and fzf are required for memo_files" >&2
    exit 1
  fi

  local result
  result=$(rg --files --glob "*.gpg" "$NOTES_DIR" | fzf --preview "gpg --quiet --decrypt {} 2>/dev/null | head -100")

  [[ -z "$result" ]] && return

  memo "$result"
}

memo_delete() {
  local force=""
  while [ "$1" = "--force" ]; do
    force="1"
    shift
  done

  if [ $# -eq 0 ]; then
    printf "No memo filename provided.\n"
    return 1
  fi

  # collect files that exist
  delete_list=()
  for target in "$@"; do
    file=$(find_note_file "$target") || {
      printf "Memo not found: %s\n" "$target"
      continue
    }
    delete_list+=("$file")
  done

  # nothing to delete
  if [ ${#delete_list[@]} -eq 0 ]; then
    return 1
  fi

  # prompt once for all files unless --force
  if [ -z "$force" ]; then
    printf "Are you sure you want to delete the following files?\n"
    printf "  %s\n" "${delete_list[@]}"
    read -rp "[y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      printf "Deletion cancelled.\n"
      return 1
    fi
  fi

  if [ ${#delete_list[@]} -gt 0 ]; then
    rm -f "${delete_list[@]}"
    printf "Deleted: %s\n" "${delete_list[*]}"
    memo_cache "${delete_list[@]}"
  fi
}

memo_grep() {
  if ! check_cmd gpg || ! check_cmd rg || ! check_cmd fzf; then
    printf "Error: gpg, rg and fzf are required for memo_grep" >&2
    exit 1
  fi

  local query="${1-""}"

  local temp_index=
  temp_index=$(mktemp)

  if [[ ! -f "$CACHE_FILE" ]]; then
    printf "Cache not found. Building it now...\n"
    memo_cache
  fi

  gpg_decrypt "$CACHE_FILE" "$temp_index"

  local selected_line

  # Print only the filename, content and line number, removing the size and hash.
  selected_line=$(
    awk -F'|' '{print $1 ":" $2 ":" $5}' "$temp_index" |
      rg --color=always "$query" |
      fzf --ansi
  )

  rm "$temp_index"

  if [[ -n "$selected_line" ]]; then
    # The filename is the first word on the selected line, up to the first colon eg. "filename.md.gpg:content:line"
    local filename line
    filename=$(printf "%s" "$selected_line" | cut -d: -f1)
    line=$(printf "%s" "$selected_line" | cut -d: -f2)

    memo "$NOTES_DIR/$filename" "$line"
  fi
}

memo_decrypt_files() {
  if [[ $# -eq 0 ]]; then
    printf "Usage: memo --decrypt <filename.gpg | glob | all> ...\n"
    return 1
  fi

  local files=()

  for target in "$@"; do
    if [[ "$target" == "all" ]]; then
      while IFS= read -r f; do
        files+=("$f")
      done < <(find "$NOTES_DIR" -type f -name "*.gpg")
      continue
    fi

    if [[ -f "$target" ]]; then
      local abs
      abs="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
      if [[ "$abs" != "$NOTES_DIR"/* ]]; then
        printf "File not in %s\n" "$NOTES_DIR"
        return 1
      fi
      [[ "$abs" == *.gpg ]] && files+=("$abs")
      continue
    fi

    local matched=0
    local f
    for f in "$NOTES_DIR"/$target; do
      if [[ -f "$f" && "$f" == *.gpg ]]; then
        files+=("$f")
        matched=1
      fi
    done
    [[ $matched -eq 0 ]] && {
      printf "File not in %s or not a .gpg file: %s\n" "$NOTES_DIR" "$target"
      return 1
    }
  done

  local f tmp out
  for f in "${files[@]}"; do
    tmp=$(mktemp)
    out="${f%.gpg}"

    if gpg_decrypt "$f" "$tmp" 2>/dev/null; then
      mv "$tmp" "$out"
      rm -f "$f"
      printf "Decrypted: %s\n" "$out"
    else
      rm -f "$tmp"
      printf "Failed to decrypt: %s\n" "$f"
    fi
  done
}

memo_encrypt_files() {
  local dry=0
  local -a exclude_patterns=()
  local -a ignore_patterns=()
  local -a recipients=()

  if ! build_gpg_recipients "$KEY_IDS" recipients; then
    return 1
  fi

  # capture .ignore into ignore_patterns[]
  while IFS= read -r pat; do
    ignore_patterns+=("$pat")
  done < <(read_ignore_file)

  # parse args
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run) dry=1 ;;
    --exclude)
      exclude_patterns+=("$2")
      shift
      ;;
    *)
      args+=("$1")
      ;;
    esac
    shift
  done

  if [[ ${#args[@]} -eq 0 ]]; then
    printf "Usage: memo encrypt <filename | glob | all> [more files …] [--dry-run] [--exclude pattern]\n"
    return 1
  fi

  shopt -s nullglob
  local files=()
  local target

  # Collect candidate files
  for target in "${args[@]}"; do
    if [[ "$target" == "all" ]]; then
      while IFS= read -r f; do
        [[ -f "$f" && "$f" != *.gpg ]] && files+=("$f")
      done < <(find "$NOTES_DIR" -type f ! -name "*.gpg")
      continue
    fi

    if [[ -f "$target" ]]; then
      local abs
      abs="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
      [[ "$abs" == "$NOTES_DIR"/* ]] || {
        printf "File not in %s\n" "$NOTES_DIR"
        shopt -u nullglob
        return 1
      }
      [[ "$abs" != *.gpg ]] && files+=("$abs")
      continue
    fi

    local matched=0
    local f
    for f in "$NOTES_DIR"/$target; do
      [[ -f "$f" && "$f" != *.gpg ]] && {
        files+=("$f")
        matched=1
      }
    done
    [[ $matched -eq 0 ]] && {
      printf "File not in %s or pattern did not match: %s\n" "$NOTES_DIR" "$target"
      shopt -u nullglob
      return 1
    }
  done
  shopt -u nullglob

  # Apply ignore/exclude filters
  local files_to_encrypt=()
  for file in "${files[@]}"; do
    local rel="${file#"$NOTES_DIR"/}"
    local skip=0

    if ((${#ignore_patterns[@]} > 0)); then
      for ig in "${ignore_patterns[@]}"; do
        # shellcheck disable=SC2053
        [[ "$rel" == $ig ]] && {
          printf "Ignored (.ignore): %s\n" "$rel"
          skip=1
          break
        }
      done
    fi
    [[ $skip -eq 1 ]] && continue

    if ((${#exclude_patterns[@]} > 0)); then
      for ex in "${exclude_patterns[@]}"; do
        # shellcheck disable=SC2053
        [[ "$rel" == $ex ]] && {
          printf "Excluded (--exclude): %s\n" "$rel"
          skip=1
          break
        }
      done
    fi
    [[ $skip -eq 1 ]] && continue

    files_to_encrypt+=("$file")
  done

  if [[ ${#files_to_encrypt[@]} -eq 0 ]]; then
    printf "Nothing to encrypt.\n"
    return 0
  fi

  # Encrypt
  if [[ $dry -eq 1 ]]; then
    for f in "${files_to_encrypt[@]}"; do
      printf "Would encrypt to: %s.gpg\n" "${f#"$NOTES_DIR"/}"
    done
  else
    local f
    for f in "${files_to_encrypt[@]}"; do
      local outfile="$f.gpg"
      if ! gpg_encrypt "$f" "$outfile.tmp"; then
        printf "Failed to encrypt: %s\n" "$f"
        rm -f "$outfile.tmp"
        return 1
      fi
      mv "$outfile.tmp" "$outfile"
      rm -f "$f"
      printf "Encrypted: %s -> %s\n" "${f#"$NOTES_DIR"/}" "${outfile#"$NOTES_DIR"/}"
    done
  fi
}

memo_encrypt() {
  local input_file="$1"
  local output_file="$2"

  gpg_encrypt "$input_file" "$output_file"
}

memo_decrypt() {
  local input_file="$1"

  gpg_decrypt "$input_file"
}

memo() {
  local input="$1"
  local lineNum="${2-1}"

  local filepath
  filepath=$(get_target_filepath "$1") || return 1

  if [[ "${MEMO_NEOVIM_INTEGRATION:-}" == true && "$EDITOR_CMD" == "nvim" ]]; then
    local gpg_file
    if gpg_file=$(get_gpg_filepath "$filepath"); then
      "$EDITOR_CMD" +"$lineNum" "$gpg_file"
    else
      create_file_header "$filepath" "$filepath.gpg"
      "$EDITOR_CMD" "$filepath.gpg"
    fi
    return
  fi

  local tmpfile
  tmpfile=$(make_or_edit_file "$filepath")

  # open tmpfile in editor
  "$EDITOR_CMD" "$tmpfile"

  # encrypt back
  local output_file
  output_file=$(get_output_gpg_filepath "$filepath")
  gpg_encrypt "$tmpfile" "$output_file"

  # cleanup
  shred -u "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
}

memo_cache() {
  $CACHE_BUILDER_BIN "$NOTES_DIR" "$CACHE_FILE" "$KEY_IDS" "$@"
}

show_help() {
  cat <<EOF
Usage: memo [OPTIONS...] FILES...

Options:
  --encrypt INFILE OUTFILE     Encrypt SOURCE_FILE into FILE.gpg
  --decrypt FILE.gpg           Decrypt file including ciphertext to stdout
  --help                       Show this message
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
    --decrypt)
      shift
      memo_decrypt "$@"
      return
      ;;
    --decrypt-files)
      shift
      memo_decrypt_files "$@"
      return
      ;;
    --encrypt)
      shift
      memo_encrypt "$@"
      return
      ;;
    --encrypt-files)
      shift
      memo_encrypt_files "$@"
      return
      ;;
    --grep)
      shift
      memo_grep "$@"
      return
      ;;
    --files)
      memo_files
      return
      ;;
    --cache)
      shift
      memo_cache "$@"
      return
      ;;
    --)
      shift
      break
      ;;
    -*)
      show_help
      exit 1
      ;;
    *)
      arg="$1"
      shift
      break
      ;;
    esac
  done

  if [[ -z "$arg" || "$arg" == "today" || "$arg" == "yesterday" || "$arg" == "tomorrow" || "$arg" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || -n "$arg" ]]; then
    memo "$arg"
    return
  fi

  # unknown option
  printf "Usage: memo [today|esterday|YYYY-MM-DD|--files|--grep|--encrypt|--decrypt|--encrypt-files|--decrypt-files|--cache]\n"
  exit 1
}

# Entrypoint
main() {
  local script_path
  script_path="$(resolve_script_path)"

  if ! check_cmd gpg; then
    printf "Error: gpg not found in PATH" >&2
    exit 1
  fi

  CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"
  load_config "$CONFIG_FILE" "$script_path"
  gpg_keys_exists "$KEY_IDS"
  create_dirs
  build_cache_builder_binary "$script_path" "$CACHE_BUILDER_BIN"

  parse_args "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly, NOT sourced
  main "$@"
fi
