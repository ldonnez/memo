#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "removes leading whitespace" {
  run _trim " aaaaa"
  assert_output "aaaaa"
}


@test "removes trailing whitespace" {
  run _trim "aaaaa "
  assert_output "aaaaa"
}
