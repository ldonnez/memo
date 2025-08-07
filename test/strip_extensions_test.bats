#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=src/memo.sh
  source "memo.sh"
}

@test "returns filename with extensions stripped" {
  local filename="test.txt.gpg"

  run strip_extensions "$filename"
  assert_output "test"
}
