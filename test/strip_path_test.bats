#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=src/memo.sh
  source "memo.sh"
}

@test "returns file with path stripped" {
  local filepath="/tmp/test/test.md"

  run strip_path "$filepath"
  assert_output "test.md"
}
