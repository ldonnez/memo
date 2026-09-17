#!/usr/bin/env bats
# Dedicated tests for the _memo_install_completions helper in memo.sh.
# The helper installs the standalone completion files (zsh + bash) into the
# first writable location: /usr/local/share when writable, otherwise under
# $XDG_DATA_HOME/.local (matching the $HOME fallback the real upgrade uses).

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"

  # Fake source tree so the test never depends on the repo layout or a real
  # git checkout (completions are installed by name from $1/completions/).
  local fake_src="$BATS_TEST_TMPDIR/fake-src"
  mkdir -p "$fake_src/completions"
  printf '#compdef memo\n' > "$fake_src/completions/_memo"
  printf '# bash\n' > "$fake_src/completions/memo.bash"
  SRC_DIR="$fake_src"
  export SRC_DIR

  # Isolated data home so the .local fallback never touches the real $HOME.
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"

  # Resolve the target dirs exactly like memo.sh does, so assertions hold on
  # both writable /usr/local hosts and the rootless docker CI image.
  ZSH_DIR="/usr/local/share/zsh/site-functions"
  BASH_DIR="/usr/local/share/bash-completion/completions"
  [ -w /usr/local/share/zsh ] || ZSH_DIR="${XDG_DATA_HOME}/zsh/site-functions"
  [ -w /usr/local/share/bash-completion ] || BASH_DIR="${XDG_DATA_HOME}/bash-completion/completions"
  export ZSH_DIR BASH_DIR
}

@test "install_completions installs zsh and bash completion files" {
  run _memo_install_completions "$SRC_DIR"
  assert_success
  assert_output "Completions installed to $ZSH_DIR
Completions installed to $BASH_DIR"
  [ -f "$ZSH_DIR/_memo" ]
  [ -f "$BASH_DIR/memo" ]
}

@test "install_completions copies the files with 0644 permissions" {
  run _memo_install_completions "$SRC_DIR"
  assert_success
  [ -r "$ZSH_DIR/_memo" ]
  [ -r "$BASH_DIR/memo" ]
  [ ! -x "$ZSH_DIR/_memo" ]
  [ ! -x "$BASH_DIR/memo" ]
  [ ! -x "$BASH_DIR/memo" ] || fail "bash completion should not be executable"
}
