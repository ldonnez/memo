#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns success when 2 file contents are equal" {
  local file1="$NOTES_DIR/test1.md"
  echo "Hello World" >"$file1"

  local file2="$NOTES_DIR/test2.md"
  echo "Hello World" >"$file2"

  run file_content_is_equal "$file1" "$file2"
  assert_success

  # Cleanup
  rm -f "$file1" "$file2"
}

@test "returns failure when file path does not exist" {
  local file1="$NOTES_DIR/does-not-exist.md"
  local file2="$NOTES_DIR/does-not-exist"

  run file_content_is_equal "$file1" "$file2"
  assert_failure

  # Cleanup
  rm -f "$file1" "$file2"
}
