#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns the absolute path the script is run" {
  run get_script_path
  assert_success
  assert_output "/opt"
}
