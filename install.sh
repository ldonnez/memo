#!/usr/bin/env bash
set -euo pipefail

REPO="ldonnez/memo"
VERSION="${VERSION:-latest}"
MEMO_INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

_get_version() {
  if [ "$VERSION" = "latest" ]; then
    curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
  else
    printf "%s" "$VERSION"
  fi
}

main() {
  local version

  if ! version=$(_get_version); then
    printf "Version not found."
    return 1
  fi

  local tmp_dir="/tmp/memo"
  local tmp_tar="/tmp/memo.tar.gz"

  # Ensure cleanup on normal exit or error.
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir' '$tmp_tar'" EXIT

  local url="https://github.com/$REPO/releases/download/$version/memo.tar.gz"
  printf "Downloading %s\n" "$url"
  curl -sSL "$url" -o $tmp_tar

  mkdir -p "$tmp_dir" && tar -xzf $tmp_tar -C $tmp_dir

  printf "Installing memo to %s...\n" "$MEMO_INSTALL_DIR"
  mkdir -p "$MEMO_INSTALL_DIR"
  install -m 0755 /tmp/memo/memo.sh "$MEMO_INSTALL_DIR"/memo

  # Completions go to the system dirs when writable, else per-user dirs.
  local zsh_dir="/usr/local/share/zsh/site-functions"
  local bash_dir="/usr/local/share/bash-completion/completions"
  [ -w /usr/local/share/zsh ] || zsh_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  [ -w /usr/local/share/bash-completion ] || bash_dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"

  mkdir -p "$zsh_dir" "$bash_dir"
  install -m 0644 /tmp/memo/completions/_memo "$zsh_dir"/_memo
  install -m 0644 /tmp/memo/completions/memo.bash "$bash_dir"/memo

  printf "Completions installed to %s\n" "$zsh_dir"
  printf "Completions installed to %s\n" "$bash_dir"

  printf "Installed memo to %s\n" "$MEMO_INSTALL_DIR"
  printf "Make sure %s is in your PATH.\n" "$MEMO_INSTALL_DIR"

  return 0
}

if [[ "${BASH_SOURCE[0]:-}" == "${0:-}" ]] || [[ "${BASH_SOURCE[0]:-}" == "" ]]; then
  main "$@"
fi
