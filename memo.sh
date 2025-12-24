#!/usr/bin/env bash

set -euo pipefail

VERSION=0.7.0 # x-release-please-version
REPO="ldonnez/memo"

###############################################################################
# Helpers (private)
###############################################################################

_dir_exists() {
  [[ -d "$1" ]]
}

_file_exists() {
  local filepath="$1"
  [[ -f "$filepath" ]]
}

_file_is_gpg() {
  local filepath="$1"
  [[ "$filepath" == *".gpg" ]]
}

_get_extension() {
  local filename="$1"
  local basename
  basename="$(basename "$filename")"

  if [[ "$basename" == *.* ]]; then
    local extension="${basename#*.}"
    printf "%s" "$extension"
  else
    printf ""
  fi
}

# /path/to/example.md -> example.md
_strip_path() {
  local filepath="$1"
  printf "%s" "${filepath##*/}"
}

# example.md.gpg -> example
_strip_extensions() {
  local filename="$1"
  while [[ "$filename" == *.* ]]; do
    filename="${filename%.*}"
  done
  printf "%s" "$filename"
}

# Check if command exists in PATH
_check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Trim leading or trailing spaces of a string
_trim() {
  local string="$1"

  # trim leading spaces
  string="${string#"${string%%[! ]*}"}"

  # trim trailing spaces
  string="${string%"${string##*[! ]}"}"
  printf "%s" "$string"
}

# Returns absolute path of given target file
# Works on relative files and will follow symlinks.
_get_absolute_path() {
  local target="$1"

  local abs_path
  abs_path=$(readlink -f "$target")

  printf "%s" "$abs_path"
}

# Check if filename matches YYYY-MM-DD format.
# Strips path and extensions before determining. (e.g example.md.gpg -> example)
_filename_is_date() {
  local filepath="$1"

  # Example: 2025-08-05.md.gpg -> 2025-08-05
  local filename
  filename=$(_strip_extensions "$(_strip_path "$filepath")")

  if [[ "$filename" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    return 0
  else
    return 1
  fi
}

###############################################################################
# Common (private)
###############################################################################

# Check if the filename ends with .txt OR .md OR .org.
# Will remove .gpg extension if present before checking, for example test.md.gpg -> test.md
_is_supported_extension() {
  local filename="$1"

  if [[ "$filename" == "-" || -z "$filename" ]]; then
    return 0
  fi

  # Remove .gpg extension if present
  local tmp_filename="${filename%.gpg}"

  local extension
  extension="$(_get_extension "$tmp_filename")"

  local -a supported_extensions
  IFS=',' read -r -a supported_extensions <<<"$SUPPORTED_EXTENSIONS"

  # Loop through the array of supported extensions
  if ((${#supported_extensions[@]} > 0)); then
    for ext in "${supported_extensions[@]}"; do
      ext=$(_trim "$ext")

      if [[ "$extension" == "$ext" ]]; then
        return 0
      fi
    done
  fi

  printf "Extension: %s not supported\n" "$extension" >&2
  return 1
}

# Validates if all the given gpg_recipients exist in GPG keyring.
_gpg_recipients_exists() {
  local recipients="$1"
  local missing_keys=()

  IFS=',' read -ra keys <<<"$recipients"

  if ((${#keys[@]} > 0)); then
    for key in "${keys[@]}"; do
      key="$(_trim "$key")"

      if ! gpg --list-keys "$key" &>/dev/null; then
        missing_keys+=("$key")
      fi
    done
  fi

  if ((${#missing_keys[@]} > 0)); then
    printf "GPG recipient(s) not found: %s\n" "${missing_keys[*]}" >&2
    exit 1
  fi
}

# Maps today, yesterday, tomorrow to YYYY-MM-DD date.
_determine_filename() {
  local input="$1"

  if [[ -z "$input" ]]; then
    # Strip .gpg extension if present
    printf "%s" "${CAPTURE_FILE%.gpg}"
    return 0
  fi

  if [[ "$input" == "today" ]]; then
    printf "%s.%s" "$(date +%F)" "$DEFAULT_EXTENSION"
    return 0
  fi

  if [[ "$input" == "yesterday" ]]; then
    printf "%s.%s" "$(date -d "yesterday" +%F 2>/dev/null || date -v-1d +%F)" "$DEFAULT_EXTENSION"
    return 0
  fi

  if [[ "$input" == "tomorrow" ]]; then
    printf "%s.%s" "$(date -d "tomorrow" +%F 2>/dev/null || date -v+1d +%F)" "$DEFAULT_EXTENSION"
    return 0
  fi

  if [[ "$input" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf "%s.%s" "$input" "$DEFAULT_EXTENSION"
    return 0
  fi

  local extension
  extension=$(_get_extension "$input")

  if [[ "$extension" == "" ]]; then
    printf "%s.%s" "$input" "$DEFAULT_EXTENSION"
    return 0
  fi

  if _is_supported_extension "$input"; then
    printf "%s" "$input"
    return 0
  fi
  return 1
}

# Returns filepath based on input file name.
_get_filepath() {
  local input="$1"

  local filename
  if filename=$(_determine_filename "$input"); then
    local filepath

    if [[ -n "$input" && "$PWD" == "$NOTES_DIR"* ]]; then
      filepath="$PWD/$input"
    elif _file_exists "$filename" && _file_is_gpg "$filename"; then
      filepath="$filename"
    else
      filepath="$NOTES_DIR/$filename"
    fi

    dirpath=$(dirname "$filepath")
    mkdir -p "$dirpath"

    printf "%s" "$filepath"
  else
    return 1
  fi
}

# Resolves the absolute path of where this script is run (it will follows symlinks)
_resolve_script_path() {
  local source="${BASH_SOURCE[0]}"
  while [ -h "$source" ]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" && pwd)"

    source="$(readlink "$source")"
    [[ $source != /* ]] && source="$dir/$source"
  done
  cd -P "$(dirname "$source")" && pwd
}

# Builds the gpg recipients (-r param in gpg) based on given gpg_recipients
# When given gpg_recipients is empty, --default-recipient-self is given, which means the first key found in the keyring is used as a recipient.
# returns array of "-r <gpg_recipient> -r <gpg_recipient2>"
#
# Usage:
#
# ```
# local -a recipients=()
#
# if ! _build_gpg_recipients "$GPG_RECIPIENTS" recipients; then
#   return 1
# fi
#
# gpg --quiet --yes --armor --encrypt "${recipients[@]}"...
# ```
_build_gpg_recipients() {
  local gpg_recipients="$1"
  local output_array="$2"

  if [[ -z "$gpg_recipients" ]]; then
    eval "$output_array+=(\"--default-recipient-self\")"
    return 0
  fi

  local IFS=',' items
  read -r -a items <<<"$gpg_recipients"

  if [[ ${#items[@]} -eq 0 ]]; then
    eval "$output_array+=(\"--default-recipient-self\")"
    return 0
  fi

  local id
  for id in "${items[@]}"; do
    id=$(_trim "$id")
    [[ -z "$id" ]] && continue

    if ! _gpg_recipients_exists "$id"; then
      printf "GPG recipient(s) not found: %s\n" "$id" >&2
      return 1
    fi

    eval "$output_array+=(\"-r\" \"$id\")"
  done
}

# Encrypts the content of given input file (path) to given output file (path)
# This will NOT encrypt the file itself only the content. (gpg --armor)
_gpg_encrypt() {
  # Sets output_path to input_path when output_path is not given
  local input_path="$1" output_path="${2-$1}"

  if ! _file_exists "$input_path"; then
    printf "File not found: %s" "$input_path"
    exit 1
  fi

  local -a recipients=()

  if ! _build_gpg_recipients "$GPG_RECIPIENTS" recipients; then
    return 1
  fi

  gpg --quiet --yes --armor -z 0 --compress-algo none --encrypt "${recipients[@]}" -o "$output_path" "$input_path"
}

# Decrypts given input file (path) to given output file (path)
# When output_path is not given (default) it will decrypt content to stdout. This is important when decrypting to external buffers like in Neovim.
_gpg_decrypt() {
  local input_path="$1" output_path="${2-""}"

  if ! _file_exists "$input_path"; then
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
    gpg --quiet --yes --output "$output_path" --decrypt "$input_path" || {
      printf "Failed to decrypt %s\n" "$input_path" >&2
      return 1
    }
  fi
}

# Creates a tempfile used for temporary storing decrypted content.
# When on Linux it will create the tempfile on memory (/dev/shm), otherwise (e.g MacOS) /tmp is used.
_make_tempfile() {
  local encrypted_file="$1"
  local relname="${encrypted_file##*/}" # remove path /path/to/2025-01-01.md.gpg -> 2025-01-01.md.gpg
  local base="${relname%.gpg}"          # remove .gpg extension 2025-01-01.md.gpg -> 2025-01-01.md

  local tmpdir
  if _dir_exists /dev/shm; then
    tmpdir="/dev/shm"
  else
    tmpdir=$(mktemp -d 2>/dev/null || printf "/tmp")
  fi

  local tmpfile="$tmpdir/memo-${base}"
  printf "%s" "$tmpfile"
}

# Checks if given path is inside $NOTES_DIR. Also works if the file is in subdir of $NOTES_DIR
# Will get absolute path and follow symlinks of given file.
_is_in_notes_dir() {
  local target="$1"

  local fullpath
  fullpath=$(_get_absolute_path "$target")

  local notes_dir
  notes_dir=$(_get_absolute_path "$NOTES_DIR")

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
# Caution! This will follow symlinks!
_get_target_filepath() {
  local input="${1-""}"
  local fullpath

  if _file_exists "$input"; then
    if _is_in_notes_dir "$input" && _file_is_gpg "$input"; then
      fullpath=$(_get_absolute_path "$input")
      printf "%s" "$fullpath"
      return 0
    else
      printf "Error: File is not a valid gpg memo in the notes directory.\n" >&2
      return 1
    fi
  else
    # File doesn't exist, generate a new one.
    _get_filepath "$input"
    return
  fi
}

# Finds note file path relative of $NOTES_DIR.
# When working dir is inside $NOTES_DIR it will return the relative path
_find_note_file() {
  local target="$1"
  local file=""

  if _file_exists "$target"; then
    file="$target"
  else
    file=$(find "$NOTES_DIR" -type f -path "*/$target" | head -n 1)
  fi

  if ! _file_exists "$file"; then
    printf "Not found: %s\n" "$target"
    return 1
  fi

  if ! _is_in_notes_dir "$file"; then
    printf "File not in %s\n" "$NOTES_DIR"
    return 1
  fi

  printf "%s" "$file"
}

_prepend_header() {
  local file="$1"
  local header="${CAPTURE_HEADER:-}"

  [[ -z "$header" ]] && return

  local os
  os=$(uname)

  if [ "$os" = "Darwin" ]; then
    sed -i '' "3i\\
$header\\
\\
\\
\\
" "$file"
    return
  fi

  sed -i "3i\\
$header\\
\\
\\
" "$file"
}

# Edits given file in temporary file.
# Creates new file with filename as header if not exists. e.g example.md -> # example
_make_or_edit_file() {
  local filepath="$1"

  local tmpfile
  tmpfile=$(_make_tempfile "${filepath##*/}")

  local gpg_file
  if gpg_file=$(_get_gpg_filepath "$filepath"); then
    _gpg_decrypt "$gpg_file" "$tmpfile"
  else
    _create_file_header "$filepath" "$tmpfile"
  fi

  printf "%s\n" "$tmpfile"
}

# Determines correct GPG file path
_get_gpg_filepath() {
  local filepath="$1"

  if _file_exists "$filepath.gpg"; then
    printf "%s.gpg\n" "$filepath"
  elif _file_is_gpg "$filepath"; then
    printf "%s\n" "$filepath"
  else
    return 1
  fi
}

# Determines the output GPG file path used before encryption
_get_output_gpg_filepath() {
  local filepath="$1"

  if _file_is_gpg "$filepath"; then
    printf "%s\n" "$filepath"
  else
    printf "%s.gpg\n" "$filepath"
  fi
}

# Creates a file header used when new file is created
_create_file_header() {
  local filepath="$1"
  local output_file="$2"

  local header
  header=$(_strip_extensions "$(_strip_path "$filepath")")
  printf "# %s\n\n\n" "$header" >"$output_file"
}

# Loads $DEFAULT_IGNORE and $NOTES_DIR/.ignore file into space separated string.
#
# Usage:
#
# ```
# local -a ignore_patterns=()
#
# while IFS= read -r pat; do
#   ignore_patterns+=("$pat")
# done < <(_read_ignore_file)
# ```
_get_ignored_files() {

  if [ -n "${DEFAULT_IGNORE:-}" ]; then
    IFS=',' read -ra defaults <<<"$DEFAULT_IGNORE"
    for pattern in "${defaults[@]}"; do
      ext=$(_trim "$pattern")

      printf "%s\n" "$pattern"
    done
  fi

  local ignore_file=$NOTES_DIR/.ignore
  if _file_exists "$ignore_file"; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in \#*) continue ;; esac
      # print the pattern so the caller can capture it
      printf "%s\n" "$line"
    done <"$ignore_file"
  fi
}

# Returns latest release version of memo by using the Github API.
_get_latest_version() {
  curl -s https://api.github.com/repos/$REPO/releases/latest | grep tag_name | cut -d '"' -f4
}

# Determines if current installed version is older then given version. Returns exit code 1 when no upgrade is necessary, otherwise will return 0.
# Caution! Does not work with version strings like v0.1.0-alpha. Wil only work with strings like v0.1.0, v0.1.2 etc.
# See test/check_upgrade_test.bats
_check_upgrade() {
  local version="$1"
  local current_version="v$VERSION"

  local newer
  newer=$(printf '%s\n' "$version" "$current_version" | sort -V | tail -n1)

  if [ "$version" = "$current_version" ]; then
    printf "Already up to date\n"
    return 1
  elif [ "$newer" = "$version" ]; then
    printf "Upgrade available: %s -> %s\n" "$current_version" "$version"
    return 0
  else
    printf "Current version (%s) is newer than latest %s?\n" "$current_version" "$version"
    return 1
  fi
}

# Syncs notes when $NOTES_DIR is a git repository
#
# Usage:
#   memo git-sync
_git_sync() {
  # Ensure it's a git repo
  if ! _dir_exists "$NOTES_DIR/.git"; then
    printf "Not a git repository.\n"
    return 1
  fi

  if ! git -C "$NOTES_DIR" pull origin main --rebase --autostash; then
    printf "Error: Conflict detected during pull.\n"
    return 1
  fi

  if git -C "$NOTES_DIR" ls-files -u | grep -q '.*'; then
    printf "Error: Conflict detected during pull. Please resolve manually.\n"
    return 1
  fi

  git -C "$NOTES_DIR" add .
  if ! git -C "$NOTES_DIR" diff-index --quiet HEAD; then
    git -C "$NOTES_DIR" commit -m "$DEFAULT_GIT_COMMIT"
    git -C "$NOTES_DIR" push origin main
    printf "Sync complete: Changes pushed.\n"
  else
    printf "Sync complete: No new commits needed.\n"
  fi
}

###############################################################################
# Core API
###############################################################################

# Interactively select a file inside notes dir using fzf.
#
# Ensures that the required commands (`gpg`, `rg`, `fzf`) are present before running.
# Uses `ripgrep` to list all note files (`*.gpg`) under NOTES_DIR.
#
# Usage:
#   memo_files
memo_files() {
  if ! _check_cmd gpg || ! _check_cmd rg || ! _check_cmd fzf; then
    printf "Error: gpg, rg and fzf are required for memo_files" >&2
    exit 1
  fi

  local result
  result=$(rg --files --glob "*.gpg" "$NOTES_DIR" | fzf --preview "gpg --quiet --decrypt {} 2>/dev/null | head -100")

  [[ -z "$result" ]] && return

  memo "$result"
}

# Decrypts a set of files that were encrypted with GPG.
#
# This function operates in-place: each `.gpg` file is decrypted and replaces the original encrypted file.
# A temporary file is used during decryption to ensure that a failed operation never overwrites the original file.
# Function supports glob patterns like <dir>/* and multiple files <file1> <file2>
#
# Usage:
#   memo_decrypt_files <file1.gpg | glob | all> [file2.gpg ...]
memo_decrypt_files() {
  if [[ $# -eq 0 ]]; then
    printf "Usage: memo decrypt-files <filename.gpg | glob | all> ...\n"
    return 1
  fi

  local files=()

  for target in "$@"; do
    if [[ "$target" == "all" ]]; then
      while IFS= read -r f; do
        files+=("$f")
        # Ensure consistent sorting on Linux/Macos with LC_ALL=C sort
      done < <(find "$NOTES_DIR" -type f -name "*.gpg" | LC_ALL=C sort)
      continue
    fi

    if _file_exists "$target"; then
      if ! _is_in_notes_dir "$target"; then
        printf "File not in %s\n" "$NOTES_DIR"
        return 1
      fi

      if _file_is_gpg "$target"; then
        files+=("$target")
      fi
      continue
    fi

    local matched=0
    local f
    for f in "$NOTES_DIR"/$target; do
      if _file_exists "$f" && _file_is_gpg "$f"; then
        files+=("$f")
        matched=1
      fi
    done
    [[ $matched -eq 0 ]] && {
      printf "File not in %s or not a .gpg file: %s\n" "$NOTES_DIR" "$target"
      return 1
    }
  done

  if [[ ${#files[@]} -eq 0 ]]; then
    printf "Nothing to decrypt.\n"
    return 0
  fi

  local f tmp out
  for f in "${files[@]}"; do
    tmp=$(mktemp)
    out="${f%.gpg}"

    if _gpg_decrypt "$f" "$tmp" 2>/dev/null; then
      mv "$tmp" "$out"
      rm -f "$f"
      printf "Decrypted: %s\n" "$out"
    else
      rm -f "$tmp"
      printf "Failed to decrypt: %s\n" "$f"
    fi
  done
}

# Encrypts a set of files using GPG, respecting user-defined rules like `.ignore` and `--exclude` patterns.
#
# Each file is encrypted in-place with `.gpg` extension using a temp file while preserving the original file name.
# Errors are reported and skipped files are logged with its source.
# Unsupported extensions are logged and skipped
# When giving `--dry-run` flag, it simulates the operation without making changes.
# The function supports glob patterns like <dir>/* and multiple files <file1> <file2>
#
# Usage:
#   memo_encrypt_files <file1|glob|all> [file2 ...] [--exclude pattern] [--dry-run]
memo_encrypt_files() {
  local dry=0
  local -a exclude_patterns=()
  local -a ignore_patterns=()
  local -a recipients=()

  if ! _build_gpg_recipients "$GPG_RECIPIENTS" recipients; then
    return 1
  fi

  # capture .ignore into ignore_patterns[]
  while IFS= read -r pat; do
    ignore_patterns+=("$pat")
  done < <(_get_ignored_files)

  # parse extra args like --dry-run, --exclude...
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
    printf "Usage: memo encrypt-files <filename | glob | all> [more files …] [--dry-run] [--exclude pattern]\n"
    return 1
  fi

  shopt -s nullglob
  local files=()
  local target

  # Collect candidate files
  for target in "${args[@]}"; do
    if [[ "$target" == "all" ]]; then
      while IFS= read -r f; do

        if _file_exists "$f" && ! _file_is_gpg "$f"; then
          files+=("$f")
        fi

        # Ensure consistent sorting on Linux/Macos with LC_ALL=C sort
      done < <(find "$NOTES_DIR" -type f ! -name "*.gpg" | LC_ALL=C sort)
      continue
    fi

    if _file_exists "$target"; then
      if ! _is_in_notes_dir "$target"; then
        printf "File not in %s\n" "$NOTES_DIR"
        shopt -u nullglob
        return 1
      fi

      if ! _file_is_gpg "$target"; then
        files+=("$target")
      fi

      continue
    fi

    local matched=0
    local f
    for f in "$NOTES_DIR"/$target; do
      if _file_exists "$f" && ! _file_is_gpg "$f"; then
        files+=("$f")
        matched=1
      fi
    done
    [[ $matched -eq 0 ]] && {
      printf "File not in %s or pattern did not match: %s\n" "$NOTES_DIR" "$target"
      shopt -u nullglob
      return 1
    }
  done
  shopt -u nullglob

  if [[ ${#files[@]} -eq 0 ]]; then
    printf "Nothing to encrypt.\n"
    return 0
  fi

  # Apply ignore/exclude filters
  local -a files_to_encrypt=()

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

    if ! _is_supported_extension "$file"; then
      skip=1
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
      if ! _gpg_encrypt "$f" "$outfile.tmp"; then
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

# Encrypts the text in given input file to given output file.
#
# It will print error when trying to encrypt an unsupported file extension.
#
# Usage:
#   memo_encrypt <input_file> <output_file>.gpg
memo_encrypt() {
  local input_file="$1"
  local output_file="$2"

  if ! _is_supported_extension "$input_file"; then
    return 1
  fi

  _gpg_encrypt "$input_file" "$output_file"
}

# Decrypts given input file with a PGP MESSAGE to stdout.
#
# Usage:
#   memo_decrypt <input_file>.gpg <output_file>
memo_decrypt() {
  local input_file="$1"

  _gpg_decrypt "$input_file"
}

# Checks if files in notes dir are correctly encrypted with gpg.
#
# Usefull to prevent leaking non encrypted data, for example, when publishing notes to a git repository.
# .ignore file is taken into account. Every pattern in .ignore will not be checked, as wel as unsupported file extensions.
#
# Usage:
#   memo_integrity_check
memo_integrity_check() {
  local -a files=()

  while IFS= read -r f; do
    [[ -f "$f" ]] && files+=("$f")
    # Ensure consistent sorting on Linux/Macos with LC_ALL=C sort
  done < <(find "$NOTES_DIR" -type f | LC_ALL=C sort)

  local -a files_to_check=()
  local -a ignore_patterns=()

  # capture .ignore into ignore_patterns[]
  while IFS= read -r pat; do
    ignore_patterns+=("$pat")
  done < <(_get_ignored_files)

  if [[ ${#files[@]} -eq 0 ]]; then
    printf "Nothing to check.\n"
    return 0
  fi

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

    if ! _file_is_gpg "$file" && ! _is_supported_extension "$file"; then
      skip=1
    fi
    [[ $skip -eq 1 ]] && continue

    files_to_check+=("$file")
  done

  if [[ ${#files_to_check[@]} -eq 0 ]]; then
    printf "Nothing to check.\n"
    return 0
  fi

  local integrity_check=0
  printf "Starting integrity check on files in %s\n" "$NOTES_DIR..."
  for f in "${files_to_check[@]}"; do
    printf "Checking %s\n" "$f..."

    if gpg --list-packets "$f" >/dev/null; then
      printf "Valid GPG-encrypted file.\n"
    else
      printf "NOT a valid GPG-encrypted file.\n"
      integrity_check=1
    fi
  done

  if [ "$integrity_check" -eq 0 ]; then
    printf "All files passed the integrity check.\n"
    return 0
  else
    printf "Some files failed the integrity check. Please investigate.\n"
    return 1
  fi
}

# Opens or creates a file for editing.
#
# A temporary plaintext file is created that is encrypted back into a `.gpg` file after editing.
# It will return error when trying to create a file with an unsupported extension.
#
# The temporary files will get deleted after encryption.
#
# Usage:
#   memo <file>
memo() {
  local input="${1-""}"

  local filepath
  filepath=$(_get_target_filepath "$input") || return 1

  local tmpfile
  tmpfile=$(_make_or_edit_file "$filepath")

  if [[ -z "$input" ]]; then
    _prepend_header "$tmpfile"
    "$EDITOR_CMD" +5 "$tmpfile"
  else
    "$EDITOR_CMD" "$tmpfile"
  fi

  local output_file
  output_file=$(_get_output_gpg_filepath "$filepath")
  _gpg_encrypt "$tmpfile" "$output_file"

  shred -u "$tmpfile" 2>/dev/null || rm -f "$tmpfile"
}

# Upgrades memo in-place when a new version is found.
#
# Will replace memo by resolving the path where the script is located, even if it is a symlink.
#
# Usage:
#   memo upgrade
memo_upgrade() {
  local latest_version
  local arg="${1-}"
  local force=0

  if [ "$arg" = "--force" ] || [ "$arg" = "-f" ]; then
    force=1
  fi

  if ! latest_version=$(_get_latest_version); then
    printf "Version not found."
    return 1
  fi

  if _check_upgrade "$latest_version"; then
    if [ "$force" -eq 0 ]; then
      # Ask to confirm upgrade
      read -r -p "Do you want to upgrade now? [Y/n] " reply
      if [ -z "$reply" ] || [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
        printf "Proceeding with upgrade...\n"
      else
        printf "Upgrade cancelled.\n"
        return 0
      fi
    fi

    local url="https://github.com/$REPO/releases/download/$latest_version/memo.tar.gz"

    local script_path
    script_path=$(_resolve_script_path)

    printf "Downloading %s\n" "$url"
    curl -sSL "$url" -o /tmp/memo.tar.gz

    mkdir -p /tmp/memo && tar -xzf /tmp/memo.tar.gz -C /tmp/memo

    printf "Upgrade memo in %s...\n" "$script_path"
    install -m 0700 /tmp/memo/memo.sh "$script_path"/memo

    rm -rf /tmp/memo
    rm -rf /tmp/memo.tar.gz

    printf "Upgrade success!\n"
    return 0
  fi
}

# Syncs notes when $NOTES_DIR is a git repository
#
# Usage:
#   memo sync git
memo_sync() {
  local arg="${1-}"

  case "$arg" in
  git)
    _git_sync
    ;;
  "")
    cat <<EOF
Usage: memo sync git

Available options:
  git    Sync notes using git
EOF
    ;;
  *)
    cat <<EOF
Unknown option: $1

Usage: memo sync git
EOF
    return 1
    ;;
  esac
}

# Uninstalls memo
#
# Will delete memo by resolving the path where the script is located, even if it is a symlink.
#
# Usage:
#   memo uninstall
memo_uninstall() {
  # Ask to confirm uninstall
  read -r -p "Are you sure you want to uninstall memo? [Y/n] " reply
  if [ -z "$reply" ] || [ "$reply" = "y" ] || [ "$reply" = "Y" ]; then
    printf "Proceeding with uninstall...\n"
  else
    printf "Uninstall cancelled.\n"
    return 0
  fi

  local script_path
  script_path=$(_resolve_script_path)

  rm -rf "$script_path/memo"
  printf "Deleted %s\n" "$script_path/memo"

  printf "Uninstall completed.\n"
}

# Prints current version of memo
#
# Usage:
#   memo version
memo_version() {
  printf "%s\n" "v$VERSION"
}

show_help() {
  cat <<EOF
Usage: memo [FILE] [LINE]
       memo [COMMAND] [ARGS...]

Description:
  Opening and editing files is the default action:
    - "memo"           Opens default memo or creates it if missing
    - "memo FILE"      Opens or creates a file named FILE

Commands:
  encrypt INPUTFILE OUTPUTFILE      Encrypt INFILE into OUTFILE.gpg
  decrypt FILE.gpg                  Decrypt FILE.gpg and print plaintext to stdout

  encrypt-files [FILES...]          Encrypt files in-place inside notes dir
                                      - Accepts 'all' or explicit files
                                      - Supports glob patterns (e.g. dir/*)

  decrypt-files [FILES...]          Decrypt .gpg files in-place inside notes dir
                                      - Accepts 'all' or explicit .gpg files
                                      - Supports glob patterns (e.g. dir/*.gpg)

  files                             Browse all files in fzf (decrypts preview)
  integrity-check                   Checks the integrity of all the files inside notes dir. Does not check files ignored with .ignore.
  sync [git]                        Creates local git commit: $DEFAULT_GIT_COMMIT with changes and pushes to remote.
                                      - Accepts 'git'

  upgrade                           Upgrades memo in-place
  uninstall                         Uninstalls memo

  version                           Print current version
  help                              Show this help message

Examples:
  memo                                Open default file
  memo todo.md                        Open or create "todo.md" inside notes dir
  memo encrypt notes.txt out.gpg    Encrypt notes.txt into out.gpg
  memo decrypt out.gpg              Decrypt out.gpg to stdout
  memo encrypt-files all            Encrypt all files in notes dir
  memo decrypt-files *.gpg          Decrypt matching .gpg files
EOF
}

###############################################################################
# Setup
###############################################################################

# Set default global variables
# Variables prefixed with _ should not be overriden in $XDG_CONFIG_HOME/.config/memo
_set_default_values() {
  : "${GPG_RECIPIENTS:=}"
  : "${NOTES_DIR:=$HOME/notes}"
  : "${EDITOR_CMD:=${EDITOR:-nano}}"
  : "${SUPPORTED_EXTENSIONS:="md,org,txt"}"
  : "${DEFAULT_EXTENSION:="md"}"
  : "${CAPTURE_FILE:=inbox.$DEFAULT_EXTENSION}"
  : "${DEFAULT_IGNORE:=".ignore,.git/*,.DS_store,.gitignore"}"
  : "${DEFAULT_GIT_COMMIT:=$(hostname): sync $(date '+%Y-%m-%d %H:%M:%S')}"
  : "${CAPTURE_HEADER:=## $(date '+%Y-%m-%d %H:%M')}"
}

# Initializes $NOTES_DIR
_create_dirs() {
  # Create directories if not exist
  mkdir -p "$NOTES_DIR"
}

# Loads config from config file (default: ~/.config/memo/config)
_load_config() {
  local config_file="$1"

  _set_default_values

  if _file_exists "$config_file"; then
    # shellcheck source=/dev/null
    source "$config_file"
  fi
}

_parse_args() {
  local arg="${1-""}"

  while [ $# -gt 0 ]; do
    case "$1" in
    help)
      show_help
      exit 0
      ;;
    decrypt)
      shift
      memo_decrypt "$@"
      return
      ;;
    decrypt-files)
      shift
      memo_decrypt_files "$@"
      return
      ;;
    encrypt)
      shift
      memo_encrypt "$@"
      return
      ;;
    encrypt-files)
      shift
      memo_encrypt_files "$@"
      return
      ;;
    integrity-check)
      shift
      memo_integrity_check
      return
      ;;
    files)
      memo_files
      return
      ;;
    sync)
      shift
      memo_sync "$@"
      return
      ;;
    upgrade)
      shift
      memo_upgrade "$@"
      return
      ;;
    uninstall)
      memo_uninstall
      return
      ;;
    version)
      memo_version
      return
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
  printf "Usage: memo [today|esterday|YYYY-MM-DD|files|encrypt|decrypt|encrypt-files|decrypt-files|integrity-check|git-sync|upgrade|uninstall]\n"
  exit 1
}

# Entrypoint
main() {
  if ! _check_cmd gpg; then
    printf "Error: gpg not found in PATH" >&2
    exit 1
  fi

  CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"
  _load_config "$CONFIG_FILE"
  _create_dirs

  _parse_args "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly, NOT sourced
  main "$@"
fi
