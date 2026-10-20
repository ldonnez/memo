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
  # Run in subshell to avoid collision with other tests
  (
    local VERSION="0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() {
      printf "v0.2.0"
    }

    run memo_upgrade <<<""
    assert_success
    assert_line --index 0 "Upgrade available: v0.1.0 -> v0.2.0"
    assert_line --index 1 "Proceeding with upgrade..."
    assert_line --index 2 "Downloading https://github.com/ldonnez/memo/releases/download/v0.2.0/memo.tar.gz"
    assert_line --index 3 "Upgrade memo in $(_resolve_script_path)..."
    assert_line --partial "Zsh completion installed to "
    assert_line --partial "Bash completion installed to "
    [[ "${lines[${#lines[@]} - 1]}" == "Upgrade success!" ]]
  )
}

@test "Upgrades memo when --force is given" {
  # Run in subshell to avoid collision with other tests
  (
    local VERSION="0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() {
      printf "v0.2.0"
    }

    run memo_upgrade "--force"
    assert_success
    assert_line --index 0 "Upgrade available: v0.1.0 -> v0.2.0"
    assert_line --index 1 "Downloading https://github.com/ldonnez/memo/releases/download/v0.2.0/memo.tar.gz"
    assert_line --index 2 "Upgrade memo in $(_resolve_script_path)..."
    assert_line --partial "Zsh completion installed to "
    assert_line --partial "Bash completion installed to "
    [[ "${lines[${#lines[@]} - 1]}" == "Upgrade success!" ]]
  )
}

@test "Does not upgrade when not confirming" {
  # Run in subshell to avoid collision with other tests
  (
    local VERSION="0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() {
      printf "v0.2.0"
    }

    run memo_upgrade <<<"n"
    assert_success
    assert_output "Upgrade available: v0.1.0 -> v0.2.0
Upgrade cancelled."
  )
}

@test "Does not upgrade when latest version = current version" {
  # Run in subshell to avoid collision with other tests
  (
    local VERSION="0.1.0"

    # Mock latest version
    # shellcheck disable=SC2329
    _get_latest_version() {
      printf "v0.1.0"
    }

    run memo_upgrade
    assert_success
    assert_output "Already up to date"
  )
}

@test "Does not upgrade when curl can't resolve host" {
  # Run in subshell to avoid collision with other tests
  (
    local VERSION="0.1.0"

    # Mock curl
    # shellcheck disable=SC2329
    curl() {
      return 6
    }

    run memo_upgrade
    assert_failure
    assert_output "Error: could not fetch the latest version from GitHub (curl exit code 6)."
  )
}

@test "Fails when the latest version cannot be parsed from the GitHub response" {
  # Run in subshell to avoid collision with other tests
  (
    # Mock curl with a response that has no tag_name
    # shellcheck disable=SC2329
    curl() {
      printf '%s\n' '{"message": "Mocked response without tag_name"}'
      return 0
    }

    run memo_upgrade
    assert_failure
    assert_output "Error: could not parse the latest version from GitHub's response."
  )
}

@test "downloads and extracts upgrades in a private temporary directory" {
  local curl_target="$TEST_HOME/upgrade-curl-target"
  local tar_args="$TEST_HOME/upgrade-tar-args"

  (
    local VERSION="0.1.0"

    # shellcheck disable=SC2329
    _get_latest_version() {
      printf "v0.2.0"
    }
    # shellcheck disable=SC2329
    curl() {
      printf '%s' "${4-}" >"$curl_target"
    }
    # shellcheck disable=SC2329
    tar() {
      printf '%s\n' "$@" >"$tar_args"
    }

    run memo_upgrade --force
    assert_success
  )

  local downloaded_to
  downloaded_to=$(cat "$curl_target")
  [[ "$downloaded_to" == "${TMPDIR:-/tmp}"/memo-upgrade.*/memo.tar.gz ]]
  [[ "$downloaded_to" != "/tmp/memo.tar.gz" ]]
  run grep -E -- "memo-upgrade\.[^/]+" "$tar_args"
  assert_success

  command rm -rf "${downloaded_to%/*}"
}
