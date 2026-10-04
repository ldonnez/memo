#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=install.sh
  source "install.sh"

  # Mock external commands
  # shellcheck disable=SC2329
  curl() {
    return 0
  }
  # shellcheck disable=SC2329
  install() {
    return 0
  }
  # shellcheck disable=SC2329
  rm() {
    return 0
  }
  # shellcheck disable=SC2329
  tar() {
    return 0
  }

  # Resolve the target dirs exactly like install.sh does.
  ZSH_DIR="/usr/local/share/zsh/site-functions"
  BASH_DIR="/usr/local/share/bash-completion/completions"

  if ! mkdir -p "$ZSH_DIR" 2>/dev/null || [ ! -w "$ZSH_DIR" ]; then
    ZSH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
  fi

  if ! mkdir -p "$BASH_DIR" 2>/dev/null || [ ! -w "$BASH_DIR" ]; then
    BASH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
  fi

  export ZSH_DIR BASH_DIR
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "Installs latest version of memo" {
  # Mock latest version
  # shellcheck disable=SC2329
  _get_version() {
    printf "v0.2.0"
  }

  run main
  assert_success
  assert_line --index 0 --partial "Downloading https://github.com/ldonnez/memo/releases/download/v0.2.0/memo.tar.gz"
  assert_line --index 1 "Installing memo to $TEST_HOME/.local/bin..."
  assert_line --partial "Zsh completion installed to $ZSH_DIR"
  assert_line --partial "Bash completion installed to $BASH_DIR"
  [[ "${lines[${#lines[@]} - 1]}" == "Make sure $TEST_HOME/.local/bin is in your PATH." ]]
  [[ "${lines[${#lines[@]} - 2]}" == "Installed memo to $TEST_HOME/.local/bin" ]]
}

@test "Does not install memo when curl could not resolve host" {
  # Run in separate subshell to avoid collision with other tests
  (
    # Mock curl
    # shellcheck disable=SC2329
    curl() {
      return 6 # Return cURL error code 6 for "Couldn't resolve host"
    }

    run main
    assert_failure
    assert_output "Error: could not fetch the latest version from GitHub (curl exit code 6)."
  )
}

@test "Fails when the latest version cannot be parsed from the GitHub response" {
  # Run in separate subshell to avoid collision with other tests
  (
    # Mock curl with a response that has no tag_name
    # shellcheck disable=SC2329
    curl() {
      printf '%s\n' '{"message": "Mocked response without tag_name"}'
      return 0
    }

    run main
    assert_failure
    assert_output "Error: could not parse the latest version from GitHub's response."
  )
}
