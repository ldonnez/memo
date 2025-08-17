#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/{,.}*
}

@test "reads ignore file" {
  local ignore="$NOTES_DIR/.ignore"
  printf "*.txt\n
.git\n" >"$ignore"

  run read_ignore_file
  assert_success
  assert_output ".ignore
*.txt
.git"
}

@test "returns empty when .ignore file does not exist" {
  run read_ignore_file
  assert_success
  assert_output ""
}
