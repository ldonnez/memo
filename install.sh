#!/usr/bin/env bash
set -euo pipefail

REPO="ldonnez/memo"
VERSION="${VERSION:-latest}"
MEMO_INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Prints latest release version of memo. Prints an explicit error and exits
# non-zero when the version cannot be determined.
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

_get_version() {
  if [ "$VERSION" = "latest" ]; then
    _get_latest_version
  else
    printf "%s" "$VERSION"
  fi
}

main() {
  local version

  if ! version=$(_get_version); then
    return 1
  fi

  local tmp_dir="/tmp/memo"
  local tmp_tar="/tmp/memo.tar.gz"

  # Ensure cleanup on normal exit or error.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir' '$tmp_tar'" EXIT

  local url="https://github.com/$REPO/releases/download/$version/memo.tar.gz"
  printf "Downloading %s\n" "$url"
  curl -sSL "$url" -o "$tmp_tar"

  mkdir -p "$tmp_dir"
  tar -xzf "$tmp_tar" -C "$tmp_dir"

  printf "Installing memo to %s...\n" "$MEMO_INSTALL_DIR"
  mkdir -p "$MEMO_INSTALL_DIR"
  install -m 0755 "$tmp_dir/memo.sh" "$MEMO_INSTALL_DIR/memo"

  # Completions go to the system dirs when writable, else per-user dirs.
  local zsh_dir="/usr/local/share/zsh/site-functions"
  local bash_dir="/usr/local/share/bash-completion/completions"

  if ! mkdir -p "$zsh_dir" 2>/dev/null || [ ! -w "$zsh_dir" ]; then
    zsh_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  fi

  if ! mkdir -p "$bash_dir" 2>/dev/null || [ ! -w "$bash_dir" ]; then
    bash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
  fi

  mkdir -p "$zsh_dir" "$bash_dir"

  install -m 0644 "$tmp_dir/completions/_memo" "$zsh_dir/_memo"
  install -m 0644 "$tmp_dir/completions/memo.bash" "$bash_dir/memo"

  printf "Zsh completion installed to %s\n" "$zsh_dir"
  printf "Bash completion installed to %s\n" "$bash_dir"

  if [ "$zsh_dir" != "/usr/local/share/zsh/site-functions" ]; then
    printf "Add this to your ~/.zshrc before compinit to enable it:\n"
    printf "  fpath=( %s \$fpath )\n" "$zsh_dir"
  fi

  if [ "$bash_dir" != "/usr/local/share/bash-completion/completions" ]; then
    printf "The per-user dir is picked up automatically when bash-completion is installed.\n"
  fi

  printf "Installed memo to %s\n" "$MEMO_INSTALL_DIR"
  printf "Make sure %s is in your PATH.\n" "$MEMO_INSTALL_DIR"

  return 0
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]] || [[ "${BASH_SOURCE[0]:-}" == "" ]]; then
  main "$@"
fi
