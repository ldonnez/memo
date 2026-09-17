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
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "Installs latest version of memo" {
  # Mock latest version
  # shellcheck disable=SC2329
  _get_version() { printf "v0.2.0"; }

  run main
  assert_success
  assert_line --index 0 --partial "Downloading https://github.com/ldonnez/memo/releases/download/v0.2.0/memo.tar.gz"
  assert_line --index 1 "Installing memo to $TEST_HOME/.local/bin..."
  assert_line --index 2 --partial "Completions installed to"
  assert_line --index 3 --partial "Completions installed to"
  assert_line --index 4 "Installed memo to $TEST_HOME/.local/bin"
  assert_line --index 5 "Make sure $TEST_HOME/.local/bin is in your PATH."
}

@test "Does not install memo curl could not resolve host" {
  # Run in separate subshell to avoid collision with other tests
  (
    # Mock curl
    # shellcheck disable=SC2329
    curl() {
      return 6 # Return cURL error code 6 for "Couldn't resolve host"
    }

    run main
    assert_failure
    assert_output "Version not found."
  )
}
