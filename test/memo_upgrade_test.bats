#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"

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
  rm -rf "/tmp/memo"
}

@test "Upgrades memo when confirming" {
  # Run in subshell to avaoid collision with other tests
  (
    local VERSION="v0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() { printf "v0.2.0"; }

    # Mock determine tarball
    # shellcheck disable=SC2329
    _build_tarball_name() { printf "memo_Linux_x86_64.tar.gz"; }

    run memo_upgrade <<<""
    assert_success
    assert_output "Upgrade available: v0.1.0 -> v0.2.0
Proceeding with upgrade...
Downloading https://github.com/ldonnez/memo/releases/download/v0.2.0/memo_Linux_x86_64.tar.gz
Upgrade memo in $(_resolve_script_path)...
Upgrade cache builder in $_CACHE_BUILDER_DIR...
Upgrade success!"
  )
}

@test "Does not upgrade when not confirming" {
  # Run in subshell to avaoid collision with other tests
  (
    local VERSION="v0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() { printf "v0.2.0"; }

    # Mock determine tarball
    # shellcheck disable=SC2329
    _build_tarball_name() { printf "memo_Linux_x86_64.tar.gz"; }

    run memo_upgrade <<<"n"
    assert_success
    assert_output "Upgrade available: v0.1.0 -> v0.2.0
Upgrade cancelled."
  )
}

@test "Does not upgrade when _build_tarball_name returns exit code 1" {
  # Run in subshell to avaoid collision with other tests
  (
    local VERSION="v0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() { printf "v0.2.0"; }

    # Mock determine tarball
    # shellcheck disable=SC2329
    _build_tarball_name() { return 1; }

    run memo_upgrade <<<"y"
    assert_failure
    assert_output "Upgrade available: v0.1.0 -> v0.2.0
Proceeding with upgrade...
Something went wrong when trying to upgrade memo"
  )
}

@test "Does not upgrade when latest version = current version" {
  # Run in subshell to avoid collision with other tests
  (
    local VERSION="v0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() { printf "v0.1.0"; }

    run memo_upgrade
    assert_success
    assert_output "Already up to date"
  )
}

@test "Does not upgrade when curl can't resolve host" {
  # Run in subshell to avoid collision with other tests
  (
    local VERSION="v0.1.0"

    # Mock curl
    # shellcheck disable=SC2329
    curl() {
      return 6
    }

    run memo_upgrade
    assert_failure
    assert_output "Version not found."
  )
}
