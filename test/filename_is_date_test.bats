#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns success when 2025-01-01.md.gpg is given" {
  run _filename_is_date "2025-01-01.md.gpg"
  assert_success
}

@test "returns success when 2025-01-01.md is given" {
  run _filename_is_date "2025-01-01.md"
  assert_success
}

@test "returns success when 2025-01-01.txt is given" {
  run _filename_is_date "2025-01-01.txt"
  assert_success
}

@test "returns failure when test.md is given" {
  run _filename_is_date "test.md"
  assert_failure
}
