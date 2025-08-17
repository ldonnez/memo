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

@test "returns success when file exists" {
  local file="$NOTES_DIR/test.md"
  touch "$file"

  run file_exists "$file"
  assert_success

  # Cleanup
  rm -f "$file"
}

@test "returns failure when file does not exist" {
  run file_exists "$NOTES_DIR/does-not-exist.md"
  assert_failure
}
