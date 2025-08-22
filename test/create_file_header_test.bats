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

@test "returns filename without extensions as file header" {
  local file
  file="$NOTES_DIR/test.md"

  run create_file_header "$file" "$file"
  assert_success

  run cat "$file"
  assert_output "# test"
}

@test "returns filename without extensions as file header when filename has no extensions" {
  local file
  file="$NOTES_DIR/test"

  run create_file_header "$file" "$file"
  assert_success

  run cat "$file"
  assert_output "# test"
}
