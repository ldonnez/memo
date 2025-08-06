#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns success when command exists" {
  run check_cmd "bash"
  assert_success
}

@test "returns failure when command does not exist" {
  run check_cmd "i-do-not-exist"
  assert_failure
}
