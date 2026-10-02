setup_suite() {
  # Use readlink -f to follow symlinks here since macOS symlinks temp from /var/... to /private/var/
  TEST_HOME="$(readlink -f "$(mktemp -d)")"
  export TEST_HOME

  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  export HOME="$TEST_HOME"
  export NOTES_DIR="$TEST_HOME/notes"
  export EDITOR_CMD="true" # avoid launching an actual editor
  export GPG_RECIPIENTS="mock@example.com"
  export EXTENSION="asc"
  export CAPTURE_FILE="inbox"
  export DEFAULT_IGNORE=".ignore,.git/*,.DS_store"
  export DEFAULT_GIT_COMMIT
  DEFAULT_GIT_COMMIT="$(hostname): sync $(date '+%Y-%m-%d %H:%M:%S')"

  mkdir -p "$XDG_CONFIG_HOME/memo"
  mkdir -p "$NOTES_DIR"

  # Optional: provide a mock config file
  cat >"$XDG_CONFIG_HOME/memo/config" <<EOF
GPG_RECIPIENTS="$GPG_RECIPIENTS"
EDITOR_CMD="true"
EOF

  # Make the test gpg-agent fail instead of ask: memo.sh supplies every
  # passphrase it needs, so a prompt here means a code path would block a real
  # terminal as well. /bin/false as pinentry makes gpg error out right away,
  # turning such a regression into a failing test instead of a hanging suite.
  mkdir -p "$HOME/.gnupg"
  chmod 700 "$HOME/.gnupg"
  cat >"$HOME/.gnupg/gpg-agent.conf" <<EOF
allow-loopback-pinentry
pinentry-program /bin/false
EOF
  chmod 600 "$HOME/.gnupg/gpg-agent.conf"

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

teardown_suite() {
  # A running gpg-agent is found through a socket inside the homedir, so the
  # daemons have to go before the directory does. --kill all takes keyboxd with
  # it, and the temp home goes with them.
  gpgconf --kill all >/dev/null 2>&1 || true

  if [ -n "${TEST_HOME:-}" ]; then
    cd / || true
    rm -rf "$TEST_HOME"
  fi
}
