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

@test "encrypts file to same path and removes original" {
  local input_path="$NOTES_DIR/test.md"
  printf "Hello World" >"$input_path"

  run encrypt_file "$input_path" "$input_path.gpg"
  assert_success

  run file_exists "$input_path.gpg"
  assert_success

  run file_exists "$input_path"
  assert_failure
}
