setup_suite() {
  TEST_HOME="$(mktemp -d)"
  export TEST_HOME

  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  export HOME="$TEST_HOME"
  export NOTES_DIR="$TEST_HOME/notes"
  export JOURNAL_NOTES_DIR="$NOTES_DIR/journal"
  export CACHE_DIR="$TEST_HOME/.cache/memo"
  export CACHE_FILE="$CACHE_DIR/notes.cache"
  export EDITOR_CMD="true" # avoid launching an actual editor
  export KEY_IDS="mock@example.com"

  mkdir -p "$XDG_CONFIG_HOME/memo"
  mkdir -p "$NOTES_DIR" "$JOURNAL_NOTES_DIR" "$CACHE_DIR"

  # Optional: provide a mock config file
  cat >"$XDG_CONFIG_HOME/memo/config" <<EOF
KEY_ID="$KEY_IDS"
EDITOR_CMD="true"
EOF

  gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 1024
Name-Real: mock user
Name-Email: $KEY_IDS
Expire-Date: 0
%commit
EOF

  setup_cache_builder

  # Source your script with mocked env
  # get the containing directory of this file
  # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
  # as those will point to the bats executable's location or the preprocessed file respectively
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
  # make executables in src/ visible to PATH
  PATH="$DIR/..:$PATH"
}

setup_cache_builder() {
  # Set paths
  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_DIRNAME}")/" && pwd)"
  BIN_DIR="$PROJECT_ROOT/bin"

  mkdir -p "$BIN_DIR"

  # Build the Go binary
  printf "Building cache_builder...\n"
  (cd "$PROJECT_ROOT" && go build -o "$BIN_DIR/cache_builder" ./cmd/cache_builder)

  # Make sure it's executable
  chmod +x "$BIN_DIR/cache_builder"

  export CACHE_BUILDER_BIN=$BIN_DIR/cache_builder
}
