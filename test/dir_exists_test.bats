#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns success when dir exists" {
  # Mock /dev/shm as existing
  local dir="/tmp/test"
  mkdir -p "$dir"

  run dir_exists "$dir"
  assert_success

  rm -rf "$dir"
}

@test "returns failure when dir does not exist" {
  run dir_exists "/test"
  assert_failure
}
