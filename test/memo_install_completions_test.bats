#!/usr/bin/env bats
# Dedicated tests for the _memo_install_completions helper in memo.sh.
# The helper installs the standalone completion files (zsh + bash) into the
# first writable location: /usr/local/share when writable, otherwise under
# $XDG_DATA_HOME (matching the $HOME fallback the real upgrade uses).

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"

  # Fake source tree so the test never depends on the repo layout or a real
  # git checkout (completions are installed by name from $1/completions/).
  local fake_src="$BATS_TEST_TMPDIR/fake-src"
  mkdir -p "$fake_src/completions"
  printf '#compdef memo\n' >"$fake_src/completions/_memo"
  printf '# bash\n' >"$fake_src/completions/memo.bash"
  SRC_DIR="$fake_src"
  export SRC_DIR

  # Isolated data home so the fallback never touches the real $HOME.
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"

  # Resolve the target dirs exactly like _memo_install_completions does.
  ZSH_DIR="/usr/local/share/zsh/site-functions"
  BASH_DIR="/usr/local/share/bash-completion/completions"

  if ! mkdir -p "$ZSH_DIR" 2>/dev/null || [ ! -w "$ZSH_DIR" ]; then
    ZSH_DIR="${XDG_DATA_HOME}/zsh/site-functions"
  fi

  if ! mkdir -p "$BASH_DIR" 2>/dev/null || [ ! -w "$BASH_DIR" ]; then
    BASH_DIR="${XDG_DATA_HOME}/bash-completion/completions"
  fi

  export ZSH_DIR BASH_DIR
}

@test "install_completions installs zsh and bash completion files" {
  run _memo_install_completions "$SRC_DIR"
  assert_success
  assert_line --partial "Zsh completion installed to $ZSH_DIR"
  assert_line --partial "Bash completion installed to $BASH_DIR"
  [ -f "$ZSH_DIR/_memo" ]
  [ -f "$BASH_DIR/memo" ]
}

@test "install_completions warns when the system zsh dir is not writable" {
  if mkdir -p /usr/local/share/zsh/site-functions 2>/dev/null &&
    [ -w /usr/local/share/zsh/site-functions ]; then
    skip "system zsh completion dir is writable; fallback not in use"
  fi

  run _memo_install_completions "$SRC_DIR"
  assert_success
  assert_output --partial "Add this to your ~/.zshrc before compinit to enable it:"
  assert_output --partial "fpath=( $ZSH_DIR \$fpath )"
  assert_output --partial "Zsh completion installed to $ZSH_DIR"
  [ -f "$ZSH_DIR/_memo" ]
}

@test "install_completions copies the files with 0644 permissions" {
  run _memo_install_completions "$SRC_DIR"
  assert_success
  [ "$(stat -c '%a' "$ZSH_DIR/_memo" 2>/dev/null || stat -f '%Lp' "$ZSH_DIR/_memo")" = "644" ]
  [ "$(stat -c '%a' "$BASH_DIR/memo" 2>/dev/null || stat -f '%Lp' "$BASH_DIR/memo")" = "644" ]
}
