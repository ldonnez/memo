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

@test "reads ignore file and $DEFAULT_IGNORE" {
  local ignore="$NOTES_DIR/.ignore"
  printf "*.txt\n" >"$ignore"

  run _get_ignored_files
  assert_success
  assert_output ".ignore
.git/*
.DS_store
*.txt"
}

@test "returns only $DEFAULT_IGNORE empty when .ignore file does not exist" {
  run _get_ignored_files
  assert_success
  assert_output ".ignore
.git/*
.DS_store"
}

@test "returns empty when $DEFAULT_IGNORE is empty and .ignore file does not exist" {
  # Run in subshell to avoid collision with other tests
  (
    local DEFAULT_IGNORE

    run _get_ignored_files
    assert_success
    assert_output ""
  )
}
