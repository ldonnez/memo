#!/usr/bin/env bash
set -euo pipefail

REPO="ldonnez/memo"
VERSION="${VERSION:-latest}"
MEMO_INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
CACHE_BUILDER_INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/libexec/memo}"

# Detect OS and Arch
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$ARCH" in
x86_64) ARCH="x86_64" ;;
aarch64 | arm64) ARCH="arm64" ;;
*) echo "Unsupported arch: $ARCH" && exit 1 ;;
esac

# Resolve latest version if not specified
if [ "$VERSION" = "latest" ]; then
  VERSION=$(curl -s https://api.github.com/repos/$REPO/releases/latest |
    grep tag_name | cut -d '"' -f4)
fi

TARBALL="memo_${OS}_${ARCH}.tar.gz"
URL="https://github.com/$REPO/releases/download/$VERSION/$TARBALL"

echo "Downloading $URL..."
curl -sSL "$URL" -o /tmp/memo.tar.gz

mkdir -p /tmp/memo && tar -xzf /tmp/memo.tar.gz -C /tmp/memo

printf "Installing memo to %s...\n" "$MEMO_INSTALL_DIR"
mkdir -p "$MEMO_INSTALL_DIR"
mv /tmp/memo/memo "$MEMO_INSTALL_DIR"
chmod +x "$MEMO_INSTALL_DIR/memo"

printf "Installing cache builder to %s...\n" "$CACHE_BUILDER_INSTALL_DIR"
mkdir -p "$CACHE_BUILDER_INSTALL_DIR"
mv /tmp/memo/bin/cache_builder "$CACHE_BUILDER_INSTALL_DIR"
chmod +x "$CACHE_BUILDER_INSTALL_DIR/cache_builder"

printf "Installed memo to %s\n" "$MEMO_INSTALL_DIR"
printf "Installed cache_builder to %s\n" "$CACHE_BUILDER_INSTALL_DIR"
printf "Make sure %s is in your PATH.\n" "$MEMO_INSTALL_DIR"
