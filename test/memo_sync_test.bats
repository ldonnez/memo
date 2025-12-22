#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "shows help when given no arguments" {

  run memo_sync
  assert_success
  assert_output "Usage: memo sync git

Available options:
  git    Sync notes using git"
}

@test "runs _git_sync when given git as argument" {
  # Run in subshell to prevent collision with other tests
  (
    # mock git_sync
    # shellcheck disable=SC2329
    _git_sync() {
      printf "_git_sync called\n"
    }

    run memo_sync "git"
    assert_success
    assert_output "_git_sync called"
  )
}
