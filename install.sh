#!/usr/bin/env bash
set -euo pipefail

REPO="ldonnez/memo"
VERSION="${VERSION:-latest}"
MEMO_INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
CACHE_BUILDER_INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/libexec/memo}"

_determine_arch() {
  local arch
  arch="$(uname -m)"

  if [ "$arch" = "x86_64" ]; then
    printf "x86_64\n"
  elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
    printf "arm64\n"
  else
    printf "Unsupported arch: %s\n" "$arch" >&2
    return 1
  fi
}

_build_tarball_name() {
  local os
  os=$(uname -s)

  if [ "$os" != "Darwin" ] && [ "$os" != "Linux" ]; then
    printf "Unsupported OS: %s\n" "$os" >&2
    return 1
  fi

  local arch
  if arch=$(_determine_arch); then
    printf "memo_%s_%s.tar.gz" "$os" "$arch"
    return 0
  fi
  return 1
}

_get_version() {
  # Resolve latest version if not specified
  if [ "$VERSION" = "latest" ]; then
    curl -s https://api.github.com/repos/$REPO/releases/latest |
      grep tag_name | cut -d '"' -f4
  else
    curl -s https://api.github.com/repos/$REPO/releases/"$VERSION" |
      grep tag_name | cut -d '"' -f4
  fi
}

main() {
  local version

  if ! version=$(_get_version); then
    printf "Version not found."
    return 1
  fi

  if tarball=$(_build_tarball_name); then
    local url="https://github.com/$REPO/releases/download/$version/$tarball"

    printf "Downloading %s\n" "$url"
    curl -sSL "$url" -o /tmp/memo.tar.gz

    mkdir -p /tmp/memo && tar -xzf /tmp/memo.tar.gz -C /tmp/memo

    printf "Installing memo to %s...\n" "$MEMO_INSTALL_DIR"
    mkdir -p "$MEMO_INSTALL_DIR"
    install -m 0700 /tmp/memo/memo "$MEMO_INSTALL_DIR"/memo

    printf "Installing cache builder to %s...\n" "$CACHE_BUILDER_INSTALL_DIR"
    mkdir -p "$CACHE_BUILDER_INSTALL_DIR"
    install -m 0700 /tmp/memo/bin/cache_builder "$CACHE_BUILDER_INSTALL_DIR"/cache_builder

    rm -rf /tmp/memo
    rm -rf /tmp/memo.tar.gz

    printf "Installed memo to %s\n" "$MEMO_INSTALL_DIR"
    printf "Installed cache_builder to %s\n" "$CACHE_BUILDER_INSTALL_DIR"
    printf "Make sure %s is in your PATH.\n" "$MEMO_INSTALL_DIR"

    return 0
  fi

  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Script is being executed directly, NOT sourced
  main "$@"
fi
