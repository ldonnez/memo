#!/usr/bin/env bash
set -euo pipefail

REPO="ldonnez/memo"
VERSION="${VERSION:-latest}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Detect OS and Arch
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported arch: $ARCH" && exit 1 ;;
esac

# Resolve latest version if not specified
if [ "$VERSION" = "latest" ]; then
    VERSION=$(curl -s https://api.github.com/repos/$REPO/releases/latest \
      | grep tag_name | cut -d '"' -f4)
fi

TARBALL="memo_${VERSION}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/$REPO/releases/download/$VERSION/$TARBALL"

echo "Downloading $URL..."
curl -sSL "$URL" -o /tmp/memo.tar.gz

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
tar -xzf /tmp/memo.tar.gz -C "$INSTALL_DIR"

chmod +x "$INSTALL_DIR/memo" "$INSTALL_DIR/memo-cache"

echo "✅ Installed memo $VERSION to $INSTALL_DIR"
echo "Make sure $INSTALL_DIR is in your PATH."
