setup_suite() {
  # Use readlink -f to follow symlinks here since macOS symlinks temp from /var/... to /private/var/
  TEST_HOME="$(readlink -f "$(mktemp -d)")"
  export TEST_HOME

  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  export HOME="$TEST_HOME"
  export NOTES_DIR="$TEST_HOME/notes"
  export EDITOR_CMD="true" # avoid launching an actual editor
  export GPG_RECIPIENTS="mock@example.com"
  export SUPPORTED_EXTENSIONS="md,org,txt"
  export DEFAULT_EXTENSION="md"
  export CAPTURE_FILE="inbox.$DEFAULT_EXTENSION"
  export DEFAULT_IGNORE=".ignore,.git/*,.DS_store"
  export DEFAULT_GIT_COMMIT
  DEFAULT_GIT_COMMIT="$(hostname): sync $(date '+%Y-%m-%d %H:%M:%S')"
  export CAPTURE_HEADER
  CAPTURE_HEADER="## $(date '+%Y-%m-%d %H:%M')"

  mkdir -p "$XDG_CONFIG_HOME/memo"
  mkdir -p "$NOTES_DIR"

  # Optional: provide a mock config file
  cat >"$XDG_CONFIG_HOME/memo/config" <<EOF
GPG_RECIPIENTS="$GPG_RECIPIENTS"
EDITOR_CMD="true"
EOF

  gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 1024
Name-Real: mock user
Name-Email: $GPG_RECIPIENTS
Expire-Date: 0
%commit
EOF

  # Source your script with mocked env
  # get the containing directory of this file
  # use $BATS_TEST_FILENAME instead of ${BASH_SOURCE[0]} or $0,
  # as those will point to the bats executable's location or the preprocessed file respectively
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" >/dev/null 2>&1 && pwd)"
  # make executables in src/ visible to PATH
  PATH="$DIR/..:$PATH"
}
