#!/usr/bin/env bash

set -euo pipefail

VERSION=0.11.2 # x-release-please-version
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

# Supported note extensions memo reads. New notes are written with $EXTENSION,
# which is added to this list once the config is loaded (_resolve_note_extensions).
SUPPORTED_EXTENSIONS=("asc" "gpg")

# Whether filepath is an encrypted note, so any supported extension is accepted
_file_is_gpg() {
  local filepath="$1"
  local ext

  for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
    [[ "$filepath" == *".$ext" ]] && return 0
  done

  return 1
}

# Strips the note extension of given path (e.g example.md.gpg -> example.md)
# Only the trailing one is stripped, the rest of the name is kept as given.
_strip_note_extension() {
  local filepath="$1"
  local ext

  for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
    if [[ "$filepath" == *".$ext" ]]; then
      filepath="${filepath%."$ext"}"
      break
    fi
  done

  printf "%s" "$filepath"
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

# Ensures filepath has a note extension: one that is already there is kept, so
# notes written as .gpg keep their name, otherwise $EXTENSION is appended.
_as_gpg() {
  local filepath="$1"

  if _file_is_gpg "$filepath"; then
    printf "%s" "$filepath"
    return 0
  fi

  printf "%s.%s" "$filepath" "$EXTENSION"
}

_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$@" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$@" | awk '{print $1}'
  else
    printf '%s\n' "Error: no SHA-256 tool available" >&2
    return 1
  fi
}

###############################################################################
# Common (private)
###############################################################################

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
    return 1
  fi
}

# Maps today, yesterday, tomorrow to YYYY-MM-DD date. Everything else is
# returned as given.
_determine_filename() {
  local input="$1"

  if [[ -z "$input" ]]; then
    printf "%s" "$CAPTURE_FILE"
    return 0
  fi

  if [[ "$input" == "today" ]]; then
    printf "%s" "$(date +%F)"
    return 0
  fi

  if [[ "$input" == "yesterday" ]]; then
    printf "%s" "$(date -d "yesterday" +%F 2>/dev/null || date -v-1d +%F)"
    return 0
  fi

  if [[ "$input" == "tomorrow" ]]; then
    printf "%s" "$(date -d "tomorrow" +%F 2>/dev/null || date -v+1d +%F)"
    return 0
  fi

  # Every other input is used as given. The note extension is not decided here:
  # _as_gpg appends the configured one, so it also stays out of the way of a name
  # that already carries a supported extension.
  printf "%s" "$input"
}

# Returns filepath based on input file name.
_get_filepath() {
  local input="$1"

  local filename
  if filename=$(_determine_filename "$input"); then
    local filepath

    # An input given while inside the notes dir is taken as relative to it, so
    # `cd` into a subdir and refer to its notes by name. _is_in_notes_dir
    # compares per path component, so a sibling dir is not mistaken for one.
    if [[ -n "$input" ]] && _is_in_notes_dir "$PWD"; then
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
      continue
    fi

    eval "$output_array+=(\"-r\" \"$id\")"
  done
}

# Encrypts the content of given input file (path) to given output file (path)
# This will NOT encrypt the file itself only the content. (gpg --armor)
# When no second argument is given we interpet content from stdin
# When the third argument is 'true' the content is encrypted with a passphrase
# instead of a recipient key (gpg --symmetric)
_gpg_encrypt() {
  local output_path="$1"
  local input="${2-}"
  local symmetric="${3:-false}"

  local -a opts=()

  if [[ "$symmetric" == "true" ]]; then
    # pinentry has to be able to ask for the passphrase, so --batch and --no-tty
    # are left out here. _gpg_run adds the options for a configured passphrase.
    opts=(--yes --armor -z 0 --compress-algo none --symmetric --cipher-algo AES256)
  else
    local -a recipients=()

    _build_gpg_recipients "$GPG_RECIPIENTS" recipients

    if [[ ${#recipients[@]} -eq 0 ]]; then
      return 1
    fi

    opts=(--batch --no-tty --yes --armor -z 0 --compress-algo none --encrypt "${recipients[@]}")
  fi

  # If input_path is empty, gpg reads from stdin.
  if [[ -z "$input" ]]; then
    _gpg_run "${opts[@]}" -o "$(_as_gpg "$output_path")"
  else
    if ! _file_exists "$input"; then
      printf "File not found: %s\n" "$input" >&2
      return 1
    fi
    _gpg_run "${opts[@]}" -o "$(_as_gpg "$output_path")" "$input"
  fi
}

# Dumps the packets of given input file (path) to stdout
#
# Only ever used to look at a note without reading its content, so it must not
# start a prompt: gpg asks gpg-agent to unlock the session key of a passphrase
# note while dumping its packets, and --batch and --no-tty do not stop that,
# because the prompt comes from the agent. Without --pinentry-mode loopback
# gpg-agent starts pinentry, which blocks until somebody types the passphrase.
# Loopback keeps the request inside gpg, which then gives up right away and only
# reports that on stderr, so the packet dump on stdout stays usable.
_gpg_list_packets() {
  local input_path="$1"

  gpg --list-packets --batch --no-tty --pinentry-mode loopback "$input_path"
}

# Whether a file is encrypted with a passphrase rather than a recipient key
_file_is_symmetric() {
  local input_path="$1"

  [[ -s "$input_path" ]] || return 1

  # gpg exits non-zero when it cannot unlock the session key, which is expected
  # here, so the exit status is deliberately ignored. Its stderr is dropped as
  # well: looking at a note must not print anything.
  local packets
  packets="$(_gpg_list_packets "$input_path" 2>&1)" || true

  [[ "$packets" == *"symkey enc packet"* ]]
}

# Whether a file holds a gpg message memo can read: a recipient-key note or a
# passphrase note
_file_is_gpg_message() {
  local input_path="$1"

  if _file_is_symmetric "$input_path"; then
    return 0
  fi

  # stderr is dropped for the same reason as in _file_is_symmetric: gpg prints
  # the key it read the note for, and looking at a note must stay quiet.
  _gpg_list_packets "$input_path" >/dev/null 2>&1
}

# Resolves the passphrase into _MEMO_PASSPHRASE, reading MEMO_PASSPHRASE_FILE,
# MEMO_PASSPHRASE_FD or MEMO_PASSPHRASE_ENV in that order of precedence. Only the
# first line is read, which is what gpg itself takes from a passphrase file.
# Leaves _MEMO_PASSPHRASE empty when no source is set, which leaves the asking to
# pinentry. Called by _gpg_run, so a passphrase is only resolved when gpg runs.
_load_passphrase() {
  _MEMO_PASSPHRASE=""

  if [[ -n "${MEMO_PASSPHRASE_FILE:-}" ]]; then
    if ! _file_exists "$MEMO_PASSPHRASE_FILE"; then
      printf "Passphrase file not found: %s\n" "$MEMO_PASSPHRASE_FILE"
      return 1
    fi
    IFS= read -r _MEMO_PASSPHRASE <"$MEMO_PASSPHRASE_FILE" || true
  elif [[ -n "${MEMO_PASSPHRASE_FD:-}" ]]; then
    # A descriptor can only be read once, so the value is kept for the gpg calls
    # that follow, like encrypting a whole directory in one go.
    if [[ -z "${_MEMO_PASSPHRASE_FROM_FD+x}" ]]; then
      IFS= read -r _MEMO_PASSPHRASE <&"$MEMO_PASSPHRASE_FD" || true
      _MEMO_PASSPHRASE_FROM_FD="$_MEMO_PASSPHRASE"
    else
      _MEMO_PASSPHRASE="$_MEMO_PASSPHRASE_FROM_FD"
    fi
  elif [[ -n "${MEMO_PASSPHRASE_ENV:-}" ]]; then
    if [[ -z "${!MEMO_PASSPHRASE_ENV:-}" ]]; then
      printf "Passphrase environment variable not set: %s\n" "$MEMO_PASSPHRASE_ENV"
      return 1
    fi
    _MEMO_PASSPHRASE="${!MEMO_PASSPHRASE_ENV}"
  fi

  if [[ -z "$_MEMO_PASSPHRASE" ]] && _has_passphrase_source; then
    printf "Passphrase is empty\n"
    return 1
  fi
}

# Whether a passphrase source is configured at all
_has_passphrase_source() {
  [[ -n "${MEMO_PASSPHRASE_FILE:-}" || -n "${MEMO_PASSPHRASE_FD:-}" || -n "${MEMO_PASSPHRASE_ENV:-}" ]]
}

# Consumes a --passphrase-fd, --passphrase-file or --passphrase-env option by
# putting its value into the matching MEMO_PASSPHRASE_* variable
_set_passphrase_option() {
  local option="$1"
  local value="${2-}"

  if [[ -z "$value" ]]; then
    printf "Error: %s needs a value\n" "$option" >&2
    return 1
  fi

  case "$option" in
  --passphrase-file) MEMO_PASSPHRASE_FILE="$value" ;;
  --passphrase-fd) MEMO_PASSPHRASE_FD="$value" ;;
  --passphrase-env) MEMO_PASSPHRASE_ENV="$value" ;;
  esac
}

# Runs gpg with the given options.
#
# A resolved passphrase goes to gpg on file descriptor 3 through a here-string:
# stdin stays free for the note content, and the passphrase stays out of the
# process list and off disk. Without one, gpg asks pinentry as usual.
_gpg_run() {
  local -a opts=("$@")

  _load_passphrase || return 1

  if [[ -z "$_MEMO_PASSPHRASE" ]]; then
    gpg "${opts[@]}"
    return
  fi

  # The options go first: gpg stops reading options at the first file name.
  gpg --pinentry-mode loopback --passphrase-fd 3 "${opts[@]}" 3<<<"$_MEMO_PASSPHRASE"
}

# Decrypts given input file (path) to given output file (path)
# When output_path is not given (default) it will decrypt content to stdout. This is important when decrypting to external buffers like in Neovim.
# When a passphrase source is set (see _load_passphrase) the decrypt runs
# non-interactively, without asking pinentry.
_gpg_decrypt() {
  local input_path="$1" output_path="${2-""}"

  if ! _file_exists "$input_path"; then
    printf "File not found: %s\n" "$input_path" >&2
    return 1
  fi

  local -a opts=(--quiet --yes)

  # Send output to stdout.
  if [[ -z "$output_path" ]]; then
    _gpg_run "${opts[@]}" --decrypt "$input_path" || {
      printf "Failed to decrypt %s\n" "$input_path" >&2
      return 1
    }
  else
    # Redirect output to the specified file.
    _gpg_run "${opts[@]}" --output "$output_path" --decrypt "$input_path" || {
      printf "Failed to decrypt %s\n" "$input_path" >&2
      return 1
    }
  fi
}

# Creates a tempfile used for temporary storing decrypted content.
# When on Linux it will create the tempfile on memory (/dev/shm), otherwise (e.g MacOS) /tmp is used.
_make_tempfile() {
  local base
  base=$(_strip_note_extension "${1##*/}")

  local root="/tmp"
  # Use ramdisk if exists
  if _dir_exists "/dev/shm"; then
    root="/dev/shm"
  fi

  local tmpdir
  tmpdir=$(mktemp -d "$root/memo.XXXXXX") || return 1

  echo "$tmpdir/$base"
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

  # Compared per path component, so a sibling that merely starts with the same
  # characters ($NOTES_DIR-backup) is not taken for a subdir.
  if [[ "$fullpath" == "$notes_dir" || "$fullpath" == "$notes_dir/"* ]]; then
    return 0
  else
    return 1
  fi
}

# Checks if $NOTES_DIR is a git repository
_is_git_repository() {
  if ! git -C "$NOTES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s\n' "Not inside a git repository"
    exit 1
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
# Prints an explicit error and exits 1 when the version cannot be determined.
_get_latest_version() {
  local response=""
  local tag_name=""

  response=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>&1) || {
    printf "Error: could not fetch the latest version from GitHub (curl exit code %s).\n" "$?" >&2
    return 1
  }

  tag_name=$(printf '%s\n' "$response" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || true
  if [ -z "$tag_name" ]; then
    printf "Error: could not parse the latest version from GitHub's response.\n" >&2
    return 1
  fi

  printf "%s\n" "$tag_name"
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
# Uses $DEFAULT_COMMIT as commit mesasage
_git_sync() {
  # Ensure it's a git repo
  _is_git_repository

  if ! git -C "$NOTES_DIR" pull origin main --rebase --autostash; then
    printf "Error: Conflict detected during pull.\n"
    return 1
  fi

  if grep -q '.*' < <(git -C "$NOTES_DIR" ls-files -u); then
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

# Initializes git configuration for encrypted notes in a git repository
#
# Updates/creates .gitattributes to include: *.<ext> diff=${diff_name} for every supported note extension. This will make it possible that a custom diff command will be used for note files.
# It updates local git config to include a custom command (memo decrypt) to be used when generating git diffs.
# Adds a wildcard to .gitignore to prevent accidental staging of files that are not notes. (.gitignore, .gitattributes and .githooks/ are exempt)
_git_init() {
  # Ensure it's a git repo
  _is_git_repository

  printf '%s\n' "This will initialize Git configuration for encrypted memo notes:"
  printf '%s\n' "  - update .gitattributes"
  printf '%s\n' "  - update local git config to ensure git diffs are readable"
  printf '%s\n' "  - add a protective .gitignore (accident prevention)"
  printf '%s\n' "Proceed? [y/N]: "

  read -r reply
  case "$reply" in
  y | Y | yes | YES) ;;
  *)
    printf '%s\n' "Aborted."
    return 0
    ;;
  esac

  local attr_file="$NOTES_DIR/.gitattributes"
  local ignore_file="$NOTES_DIR/.gitignore"
  local diff_name="gpg"
  local textconv_cmd="memo decrypt"

  #
  # --- .gitattributes ---
  #
  touch "$attr_file"

  local ext
  local -a diff_rules=()
  local -a allow_rules=()
  for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
    diff_rules+=("*.${ext} diff=${diff_name}")
    allow_rules+=("!**/*.${ext}")
  done

  for rule in "${diff_rules[@]}"; do
    if ! grep -qxF "$rule" "$attr_file"; then
      printf '%s\n' "$rule" >>"$attr_file"
      printf '%s\n' "Added '$rule' to $attr_file"
    fi
  done

  #
  # --- git config ---
  #
  local current_textconv
  current_textconv="$(git -C "$NOTES_DIR" config --get diff.${diff_name}.textconv || true)"

  if [ "$current_textconv" != "$textconv_cmd" ]; then
    git config diff.${diff_name}.textconv "$textconv_cmd"
    printf '%s\n' "Configured diff.${diff_name}.textconv"
  fi

  #
  # --- .gitignore (accident prevention only) ---
  #
  touch "$ignore_file"

  # Ignore everything by default
  if ! grep -qxF "*" "$ignore_file"; then
    printf '%s\n' "*" >>"$ignore_file"
    printf '%s\n' "Added '*' to $ignore_file"
  fi

  # Do not ignore directories (so git can see them)
  if ! grep -qxF "!*/" "$ignore_file"; then
    printf '%s\n' "!*/" >>"$ignore_file"
    printf '%s\n' "Added '!*/' to $ignore_file"
  fi

  for allow in "${allow_rules[@]}"; do
    if ! grep -qxF "$allow" "$ignore_file"; then
      printf '%s\n' "$allow" >>"$ignore_file"
      printf '%s\n' "Added '$allow' to $ignore_file"
    fi
  done

  # Allow repo metadata
  for allow in "!.gitignore" "!.gitattributes" "!.githooks/"; do
    if ! grep -qxF "$allow" "$ignore_file"; then
      printf '%s\n' "$allow" >>"$ignore_file"
      printf '%s\n' "Added '$allow' to $ignore_file"
    fi
  done
}

# Reports a file that is left unencrypted only because its name ends in a note
# extension. Every name based check (find filter, _file_is_gpg, _as_gpg) takes
# such a file for a note, so it would be skipped in silence and end up committed
# as plaintext by `memo sync`.
_warn_unencrypted_file() {
  local filepath="$1"

  if _file_is_gpg "$filepath" && ! _file_is_gpg_message "$filepath"; then
    printf "Warning: %s ends in a note extension but is not encrypted, so it was skipped. Drop the extension to have it encrypted.\n" "${filepath#"$NOTES_DIR"/}"
  fi
}

###############################################################################
# Core API
###############################################################################

# Interactively select a file inside notes dir using fzf.
#
# Ensures that the required commands (`gpg`, `rg`, `fzf`) are present before running.
# Uses `ripgrep` to list all note files (any supported extension) under NOTES_DIR.
#
# Usage:
#   memo_files
memo_files() {
  if ! _check_cmd gpg || ! _check_cmd rg || ! _check_cmd fzf; then
    printf "Error: gpg, rg and fzf are required for memo_files" >&2
    exit 1
  fi

  # A passphrase note only previews when the passphrase reaches gpg, which is
  # what _load_passphrase covers.
  _load_passphrase || return 1

  local -a preview=(gpg --quiet)
  local preview_prefix=""

  if [[ -n "$_MEMO_PASSPHRASE" ]]; then
    # fzf runs the preview in a shell of its own, where descriptor 3 cannot be
    # set up from here. gpg reads the note from the file given as argument, so
    # stdin is free for the passphrase. Exported so the preview shell reads it
    # by name.
    export MEMO_PREVIEW_PASSPHRASE="$_MEMO_PASSPHRASE"
    preview_prefix="printf '%s' \"\$MEMO_PREVIEW_PASSPHRASE\" | "
    preview+=(--pinentry-mode loopback --passphrase-fd 0)
  fi
  preview+=(--decrypt)

  local preview_cmd
  printf -v preview_cmd '%q ' "${preview[@]}"

  local -a note_globs=()
  local ext
  for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
    note_globs+=(--glob "*.$ext")
  done

  local result
  result=$(rg --files "${note_globs[@]}" "$NOTES_DIR" | fzf --preview "$preview_prefix$preview_cmd{} 2>/dev/null | head -100")

  [[ -z "$result" ]] && return

  memo "$result"
}

# Decrypts a set of files that were encrypted with GPG.
#
# This function operates in-place: each encrypted note is decrypted and replaces the original encrypted file.
# A temporary file is used during decryption to ensure that a failed operation never overwrites the original file.
# Function supports glob patterns like <dir>/* and multiple files <file1> <file2>
#
# Usage:
#   memo_decrypt_files <file1.asc | glob | all> [file2.asc ...]
memo_decrypt_files() {
  local -a targets=()

  # A symmetric note can only be decrypted when the passphrase reaches gpg.
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --passphrase-fd | --passphrase-file | --passphrase-env)
      _set_passphrase_option "$1" "${2-}" || return 1
      shift
      ;;
    *)
      targets+=("$1")
      ;;
    esac
    shift
  done

  if [[ ${#targets[@]} -eq 0 ]]; then
    printf "Usage: memo decrypt-files [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR] <filename.asc | filename.gpg | glob | all> ...\n"
    return 1
  fi

  local files=()
  local -a note_args=()
  local ext

  # Match a note with any supported extension
  for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
    [[ ${#note_args[@]} -gt 0 ]] && note_args+=(-o)
    note_args+=(-name "*.$ext")
  done

  for target in "${targets[@]}"; do
    if [[ "$target" == "all" ]]; then
      while IFS= read -r f; do
        files+=("$f")
        # Ensure consistent sorting on Linux/Macos with LC_ALL=C sort
      done < <(find "$NOTES_DIR" -type f \( "${note_args[@]}" \) | LC_ALL=C sort)
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
      printf "File not in %s or not an encrypted note: %s\n" "$NOTES_DIR" "$target"
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
    out="$(_strip_note_extension "$f")"

    if _gpg_decrypt "$f" "$tmp" 2>/dev/null; then
      mv "$tmp" "$out"
      rm -f "$f"
      printf "Decrypted: %s\n" "$out"
    else
      printf "Failed to decrypt: %s\n" "$f"
    fi
  done
}

# Encrypts a set of files using GPG, respecting user-defined rules like `.ignore` and `--exclude` patterns.
#
# Each file is encrypted in-place with the note extension using a temp file while preserving the original file name.
# Errors are reported and skipped files are logged with its source.
# When giving `--dry-run` flag, it simulates the operation without making changes.
# The function supports glob patterns like <dir>/* and multiple files <file1> <file2>
#
# Usage:
#   memo_encrypt_files <file1|glob|all> [file2 ...] [--exclude pattern] [--dry-run]
memo_encrypt_files() {
  local dry=0
  local symmetric="false"
  local -a exclude_patterns=()
  local -a ignore_patterns=()

  # capture .ignore into ignore_patterns[]
  while IFS= read -r pat; do
    ignore_patterns+=("$pat")
  done < <(_get_ignored_files)

  # parse extra args like --dry-run, --exclude...
  local args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run) dry=1 ;;
    --symmetric) symmetric="true" ;;
    --passphrase-fd | --passphrase-file | --passphrase-env)
      _set_passphrase_option "$1" "${2-}" || return 1
      shift
      ;;
    --exclude)
      exclude_patterns+=("${2-}")
      shift
      ;;
    *)
      args+=("$1")
      ;;
    esac
    shift
  done

  if [[ "$symmetric" != "true" ]]; then
    local -a recipients=()

    _build_gpg_recipients "$GPG_RECIPIENTS" recipients

    if [[ ${#recipients[@]} -eq 0 ]]; then
      return 1
    fi
  fi

  if [[ ${#args[@]} -eq 0 ]]; then
    printf "Usage: memo encrypt-files <filename | glob | all> [more files …] [--dry-run] [--exclude pattern] [--symmetric] [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR]\n"
    return 1
  fi

  shopt -s nullglob
  local files=()
  local target
  local -a plaintext_args=()
  local -a note_args=()
  local ext

  # Exclude notes that are encrypted already, whatever extension they use
  for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
    plaintext_args+=(! -name "*.$ext")
    [[ ${#note_args[@]} -gt 0 ]] && note_args+=(-o)
    note_args+=(-name "*.$ext")
  done

  # Collect candidate files
  for target in "${args[@]}"; do
    if [[ "$target" == "all" ]]; then
      while IFS= read -r f; do

        if _file_exists "$f" && ! _file_is_gpg "$f"; then
          files+=("$f")
        fi

        # Ensure consistent sorting on Linux/Macos with LC_ALL=C sort
      done < <(find "$NOTES_DIR" -type f "${plaintext_args[@]}" | LC_ALL=C sort)

      # What the filter above dropped counts as a note by name. Report the ones
      # that hold no encrypted data, so plaintext cannot sit there unnoticed.
      while IFS= read -r f; do
        _warn_unencrypted_file "$f"

        # Ensure consistent sorting on Linux/Macos with LC_ALL=C sort
      done < <(find "$NOTES_DIR" -type f \( "${note_args[@]}" \) | LC_ALL=C sort)
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
      else
        _warn_unencrypted_file "$target"
      fi

      continue
    fi

    local matched=0
    local f
    for f in "$NOTES_DIR"/$target; do
      if _file_exists "$f" && ! _file_is_gpg "$f"; then
        files+=("$f")
        matched=1
      else
        _warn_unencrypted_file "$f"
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

    files_to_encrypt+=("$file")
  done

  if [[ ${#files_to_encrypt[@]} -eq 0 ]]; then
    printf "Nothing to encrypt.\n"
    return 0
  fi

  # Encrypt
  if [[ $dry -eq 1 ]]; then
    for f in "${files_to_encrypt[@]}"; do
      local rel="${f#"$NOTES_DIR"/}"
      printf "Would encrypt to: %s\n" "$(_as_gpg "$rel")"
    done
  else
    local f
    for f in "${files_to_encrypt[@]}"; do
      local outfile
      outfile="$(_as_gpg "$f")"
      if ! _gpg_encrypt "$outfile" "$f" "$symmetric"; then
        printf "Failed to encrypt: %s\n" "$f"
        return 1
      fi
      rm -f "$f"
      printf "Encrypted: %s -> %s\n" "${f#"$NOTES_DIR"/}" "${outfile#"$NOTES_DIR"/}"
    done
  fi
}

# Encrypts the text to given input file from stdin.
#
# Usage:
#   memo_encrypt [--symmetric] [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR] <input_file> | "stdin"
memo_encrypt() {
  local output_file=""
  local symmetric="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --symmetric) symmetric="true" ;;
    --passphrase-fd | --passphrase-file | --passphrase-env)
      _set_passphrase_option "$1" "${2-}" || return 1
      shift
      ;;
    *)
      # One output file only: a second one would silently win over the first
      if [[ -n "$output_file" ]]; then
        printf "Usage: memo encrypt [--symmetric] [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR] <output_file>\n"
        return 1
      fi
      output_file="$1"
      ;;
    esac
    shift
  done

  if [[ -z "$output_file" ]]; then
    printf "Usage: memo encrypt [--symmetric] [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR] <output_file>\n"
    return 1
  fi

  _gpg_encrypt "$output_file" "" "$symmetric"
}

# Decrypts given input file with a PGP MESSAGE to stdout.
#
# Usage:
#   memo_decrypt [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR] <input_file>.asc
memo_decrypt() {
  local input_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --passphrase-fd | --passphrase-file | --passphrase-env)
      _set_passphrase_option "$1" "${2-}" || return 1
      shift
      ;;
    *)
      # One note only: a second one would silently win over the first
      if [[ -n "$input_file" ]]; then
        printf "Usage: memo decrypt [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR] <input_file>\n"
        return 1
      fi
      input_file="$1"
      ;;
    esac
    shift
  done

  if [[ -z "$input_file" ]]; then
    printf "Usage: memo decrypt [--passphrase-fd N | --passphrase-file PATH | --passphrase-env VAR] <input_file>\n"
    return 1
  fi

  _gpg_decrypt "$input_file"
}

# Checks if files in notes dir are correctly encrypted with gpg.
#
# Usefull to prevent leaking non encrypted data, for example, when publishing notes to a git repository.
# .ignore file is taken into account. Every pattern in .ignore will not be checked.
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

    if _file_is_gpg_message "$f"; then
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
# A temporary plaintext file is created that is encrypted back into a note file after editing.
# The temporary files will get deleted after encryption.
#
# Usage:
#   memo <file>
memo() {
  local input="${1-""}"
  local filepath
  filepath=$(_get_target_filepath "$input") || return 1

  local gpg_file
  gpg_file="$(_as_gpg "$filepath")"

  local tmpfile
  tmpfile=$(_make_tempfile "$filepath") || return 1

  # Ensure cleanup on normal exit or error.
  # shellcheck disable=SC2064
  trap "shred -u '$tmpfile' 2>/dev/null; rm -rf '${tmpfile%/*}'" EXIT

  local orig_hash="-"
  local symmetric="false"

  if _file_exists "$gpg_file"; then
    # A note encrypted with a passphrase has to stay a passphrase note when it
    # is saved, so remember how it was encrypted before opening it.
    if _file_is_symmetric "$gpg_file"; then
      symmetric="true"
    fi

    orig_hash=$(
      _gpg_decrypt "$gpg_file" |
        tee "$tmpfile" |
        _sha256
    )
  else
    _create_file_header "$filepath" "$tmpfile"
  fi

  # Edit the temp file
  "$EDITOR_CMD" "$tmpfile"

  if [[ -n "$orig_hash" ]]; then
    local tmp_hash
    tmp_hash=$(_sha256 "$tmpfile")

    if [[ "$orig_hash" == "$tmp_hash" ]]; then
      printf '%s\n' "No changes detected; skipping re-encryption."
      return 0
    fi
  fi

  # Encrypt only if changed, back to the note that was opened
  _gpg_encrypt "$gpg_file" "$tmpfile" "$symmetric"
}

# Installs the bundled tab-completions to the system dirs when writable, else
# to per-user dirs that only zsh (via fpath) or XDG-aware bash-completion
# Source dir is an extracted release tarball.
#
# Usage:
#   _install_completions <source_dir>
_memo_install_completions() {
  local src_dir="${1:?source dir required}"
  local zsh_dir="/usr/local/share/zsh/site-functions"
  local bash_dir="/usr/local/share/bash-completion/completions"

  if ! mkdir -p "$zsh_dir" 2>/dev/null || [ ! -w "$zsh_dir" ]; then
    zsh_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  fi

  if ! mkdir -p "$bash_dir" 2>/dev/null || [ ! -w "$bash_dir" ]; then
    bash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
  fi

  mkdir -p "$zsh_dir" "$bash_dir"
  install -m 0644 "$src_dir/completions/_memo" "$zsh_dir/_memo"
  install -m 0644 "$src_dir/completions/memo.bash" "$bash_dir/memo"

  printf "Zsh completion installed to %s\n" "$zsh_dir"
  printf "Bash completion installed to %s\n" "$bash_dir"

  if [ "$zsh_dir" != "/usr/local/share/zsh/site-functions" ]; then
    printf "Add this to your ~/.zshrc before compinit to enable it:\n"
    printf "  fpath=( %s \$fpath )\n" "$zsh_dir"
  fi

  if [ "$bash_dir" != "/usr/local/share/bash-completion/completions" ]; then
    printf "The per-user dir is picked up automatically when bash-completion is installed.\n"
  fi
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
    local tmp_dir="/tmp/memo"
    local tmp_tar="/tmp/memo.tar.gz"

    local script_path
    script_path=$(_resolve_script_path)

    # Ensure cleanup on normal exit or error.
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir' '$tmp_tar'" EXIT

    printf "Downloading %s\n" "$url"
    curl -sSL "$url" -o /tmp/memo.tar.gz

    mkdir -p $tmp_dir && tar -xzf $tmp_tar -C $tmp_dir

    printf "Upgrade memo in %s...\n" "$script_path"
    install -m 0755 /tmp/memo/memo.sh "$script_path"/memo
    _memo_install_completions /tmp/memo

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

# Initializes git configuration for encrypted notes in a git repository
#
# Usage:
#   memo init git
memo_init() {
  local arg="${1-}"

  case "$arg" in
  git)
    _git_init
    ;;
  "")
    cat <<EOF
Usage: memo init git

Available options:
  init  ensures railguards for using memo in a git repository
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

  rm -f "$script_path/memo"
  printf "Deleted %s\n" "$script_path/memo"

  local zsh_dir="/usr/local/share/zsh/site-functions"
  local bash_dir="/usr/local/share/bash-completion/completions"
  local zsh_fallback="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  local bash_fallback="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"

  rm -f "$zsh_dir/_memo" "$zsh_fallback/_memo"
  rm -f "$bash_dir/memo" "$bash_fallback/memo"
  printf "Deleted completion files\n"

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
Usage: memo [FILE]
       memo [COMMAND] [ARGS...]

Description:
  Opening and editing files is the default action:
    - "memo"           Opens capture file or creates it if missing
    - "memo FILE"      Opens or creates a file named FILE

Commands:
  encrypt OUTPUTFILE                Encrypts the text from stdin to given outputfile
                                      - the note extension is added when OUTPUTFILE
                                        does not have one yet
                                      - --symmetric encrypts with a passphrase
                                        instead of a recipient key
                                      - --passphrase-fd N, --passphrase-file PATH,
                                        --passphrase-env VAR supply the
                                        passphrase without prompting

  decrypt FILE                        Decrypts the note FILE and print to stdout
                                      - FILE is read as given, no note extension
                                        is added or stripped
                                      - .gpg notes are read as well
                                      - --passphrase-fd N, --passphrase-file PATH,
                                        --passphrase-env VAR supply the
                                        passphrase without prompting

  encrypt-files [FILES...]          Encrypt files in-place inside notes dir
                                      - Accepts 'all' or explicit files
                                      - Supports glob patterns (e.g. dir/*)
                                      - --dry-run, --exclude pattern
                                      - --symmetric, --passphrase-fd N,
                                        --passphrase-file PATH

  decrypt-files [FILES...]          Decrypt notes in-place inside notes dir
                                      - Accepts 'all' or explicit note files
                                      - Supports glob patterns (e.g. dir/*.asc)
                                      - --passphrase-fd N, --passphrase-file PATH

  files                             Browse all files in fzf (decrypts preview)
  integrity-check                   Checks the integrity of all the files inside notes dir. Does not check files ignored with .ignore.
  sync [git]                        Creates a local git commit: $DEFAULT_GIT_COMMIT with changes and pushes to remote.
                                      - Accepts 'git'
  init [git]                        Initializes git configuration for encrypted notes in a git repository.
                                      - Accepts 'git'

  upgrade                           Upgrades memo in-place
  uninstall                         Uninstalls memo

  version                           Print current version
  help                              Show this help message

Examples:
  memo                                Open default file
  memo todo.md                        Open or create "todo.md" inside notes dir
  memo encrypt out.asc              Encrypt stdin into out.asc
  memo encrypt out                  Encrypt stdin into out.<EXTENSION>
  memo decrypt out.asc              Decrypt out.asc to stdout
  memo encrypt-files all            Encrypt all files in notes dir
  memo decrypt-files *.asc          Decrypt matching .asc files
  memo encrypt --symmetric out.asc <in.txt            Encrypt stdin, passphrase asked by pinentry
  memo encrypt --symmetric --passphrase-file pass.txt out.asc <in.txt
                                      Encrypt stdin with a passphrase from a file
  MEMO_PASSPHRASE=... memo encrypt --symmetric --passphrase-env MEMO_PASSPHRASE out.asc <in.txt
                                      Encrypt stdin with a passphrase from the environment

Notes:
  Notes are written with the .asc extension and encrypted notes with the .gpg
  extension are read as well, so notes stay where they are.
  Set EXTENSION in the config to write a different extension, e.g gpg.
  A custom EXTENSION is read as well, so those notes keep opening.
  New notes use the extension you specify (or none if omitted).
  A note encrypted with a passphrase is re-encrypted the same way when opened
  with 'memo FILE', so it never turns into a recipient-key note.

EOF
}

###############################################################################
# Setup
###############################################################################

# Set default global variables
# Variables prefixed with _ should not be overriden in $XDG_CONFIG_HOME/.config/memo
_set_default_values() {
  : "${GPG_RECIPIENTS:=}"
  : "${MEMO_PASSPHRASE_FD:=}"
  : "${MEMO_PASSPHRASE_ENV:=}"
  : "${MEMO_PASSPHRASE_FILE:=}"
  : "${EXTENSION:=asc}"
  : "${_MEMO_PASSPHRASE:=}"
  : "${NOTES_DIR:=$HOME/notes}"
  : "${EDITOR_CMD:=${EDITOR:-nano}}"
  : "${CAPTURE_FILE:=inbox.md}"
  : "${DEFAULT_IGNORE:=".ignore,.git/*,.githooks/*,.DS_store,.gitignore,.gitattributes"}"
  : "${DEFAULT_GIT_COMMIT:=$(hostname): sync $(date '+%Y-%m-%d %H:%M:%S')}"
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

  # After the config is read, so $EXTENSION can come from it
  _resolve_note_extensions
}

# Validates $EXTENSION and adds it to $SUPPORTED_EXTENSIONS when it is a new one.
# Notes memo writes are then readable again: without this, a note written with a
# custom extension would be unknown to every place that matches on the
# extensions (listing, decrypt-files, encrypt-files, _file_is_gpg, ...).
_resolve_note_extensions() {
  if [[ ! "$EXTENSION" =~ ^[A-Za-z0-9_][A-Za-z0-9_-]*$ ]]; then
    printf "Error: EXTENSION must be a bare extension, starting with a letter, digit or underscore: '%s'\n" "$EXTENSION" >&2
    return 1
  fi

  local ext
  for ext in "${SUPPORTED_EXTENSIONS[@]}"; do
    [[ "$ext" == "$EXTENSION" ]] && return 0
  done

  SUPPORTED_EXTENSIONS+=("$EXTENSION")
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
    init)
      shift
      memo_init "$@"
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

  if (($# > 0)); then
    printf "Usage: memo [FILE]\n" >&2
    exit 1
  fi

  memo "$arg"
  return
}

# Entrypoint
main() {
  if ! _check_cmd gpg; then
    printf "Error: gpg not found in PATH" >&2
    exit 1
  fi

  CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"

  # An unusable $EXTENSION is fatal, since every command works on note
  # extensions. The commands that only print text stay available though, so
  # there is a way to read how to fix the config.
  if ! _load_config "$CONFIG_FILE"; then
    case "${1-}" in
    help | version) ;;
    *)
      exit 1
      ;;
    esac
  fi

  _create_dirs

  _parse_args "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly, NOT sourced
  main "$@"
fi
